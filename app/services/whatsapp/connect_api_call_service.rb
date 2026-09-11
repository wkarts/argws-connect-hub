# frozen_string_literal: true

require 'uri'

class Whatsapp::ConnectApiCallService
  CALL_PROVIDER = 'WHATSAPP-ZAPO'

  def initialize(whatsapp_channel:, contact_phone: nil, conversation: nil, client: ConnectApi::Client.new)
    @channel = whatsapp_channel
    @contact_phone = normalize_number(contact_phone)
    @conversation = conversation
    @client = client
  end

  def capabilities
    provider = current_provider
    {
      provider: provider,
      calls: calls_supported?,
      voice: calls_supported? && voice_supported?,
      video: false
    }
  end

  def list
    ensure_call_provider!
    calls = @client.list_calls(instance_name)
    calls = calls.select { |call| call_matches_contact?(call) } if @contact_phone.present?
    sync_timeline_list(calls)
    calls
  end

  def offer(number:, is_video: false, call_duration: nil)
    ensure_call_provider!
    raise ConnectApi::Error, 'Chamadas de vídeo ainda não estão disponíveis nesta conexão.' if ActiveModel::Type::Boolean.new.cast(is_video)

    digits = number.to_s.gsub(/\D/, '')
    raise ConnectApi::Error, 'O contato não possui telefone válido para chamada.' if digits.blank?

    response = @client.offer_call(instance_name, number: digits, is_video: false, call_duration: call_duration)
    sync_timeline(
      response_call(response).merge(
        'direction' => response_call(response)['direction'].presence || 'outgoing',
        'status' => response_call(response)['status'].presence || 'ringing',
        'createdAt' => response_call(response)['createdAt'].presence || Time.current.utc.iso8601(3)
      ),
      action: 'state',
      status: 'ringing',
      direction: 'outgoing',
      terminal: false,
      peer_phone: digits
    )
    response
  end

  def accept(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    current_call = find_call_for_contact!(call_id)
    response = @client.accept_call(instance_name, call_id)
    sync_timeline(
      merged_call(current_call, response),
      action: 'state',
      status: 'answered',
      direction: call_direction(current_call, 'incoming'),
      terminal: false,
      peer_phone: @contact_phone
    )
    response
  end

  def reject(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    current_call = find_call_for_contact!(call_id)
    response = @client.reject_call(instance_name, call_id)
    sync_timeline(
      merged_call(current_call, response),
      action: 'ended',
      status: 'rejected',
      direction: call_direction(current_call, 'incoming'),
      terminal: true,
      peer_phone: @contact_phone
    )
    response
  end

  def end_call(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    current_call = find_call_for_contact!(call_id)
    response = @client.end_call(instance_name, call_id)
    sync_timeline(
      merged_call(current_call, response),
      action: 'ended',
      status: 'ended',
      direction: call_direction(current_call, nil),
      terminal: true,
      peer_phone: @contact_phone
    )
    response
  end

  def mute(call_id, muted:)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    current_call = find_call_for_contact!(call_id)
    response = @client.mute_call(instance_name, call_id, muted: muted)
    sync_timeline(
      merged_call(current_call, response).merge('muted' => ActiveModel::Type::Boolean.new.cast(muted)),
      peer_phone: @contact_phone
    )
    response
  end

  def media_ticket(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    find_call_for_contact!(call_id)
    ticket = @client.media_ticket(instance_name, call_id).to_h
    public_url = connect_api_public_url
    media_path = ticket['mediaPath'].presence || '/voice/media'

    {
      ticket: ticket['ticket'],
      expires_at: ticket['expiresAt'],
      expires_in_seconds: ticket['expiresInSeconds'],
      media_url: websocket_url(public_url, media_path)
    }
  end

  private

  def provider_config
    @provider_config ||= @channel.provider_config.to_h.deep_stringify_keys
  end

  def calls_supported?
    ActiveModel::Type::Boolean.new.cast(provider_config['calls_supported'])
  end

  def voice_supported?
    return calls_supported? if provider_config['voice_supported'].nil?

    ActiveModel::Type::Boolean.new.cast(provider_config['voice_supported'])
  end

  def instance_name
    @instance_name ||= provider_config['instance_name'].to_s.presence || raise(ConnectApi::Error, 'Instância de comunicação não provisionada.')
  end

  def current_provider
    configured = provider_config['connect_api_provider'].to_s
    return configured if configured.present?

    instance = @client.fetch_instances.find do |item|
      item = item.to_h
      (item['name'] || item['instanceName']).to_s == instance_name
    end
    (instance&.dig('integration') || instance&.dig('provider') || 'WHATSAPP-BAILEYS').to_s
  rescue ConnectApi::Error
    provider_config['connect_api_provider'].to_s.presence || 'WHATSAPP-BAILEYS'
  end

  def ensure_call_provider!
    return if calls_supported? && current_provider == CALL_PROVIDER

    raise ConnectApi::Error, 'Chamadas não estão habilitadas para esta conexão.'
  end

  def find_call_for_contact!(call_id)
    call = @client.list_calls(instance_name).find do |item|
      id = item.to_h['callId'] || item.to_h['id']
      id.to_s == call_id.to_s
    end

    if @contact_phone.present? && (!call || !call_matches_contact?(call))
      raise ConnectApi::Error, 'Chamada não encontrada nesta conversa.'
    end
    raise ConnectApi::Error, 'Chamada não encontrada.' unless call

    call
  end

  def call_matches_contact?(call)
    return true if @contact_phone.blank?

    item = call.to_h.deep_stringify_keys
    candidates = [item['number'], item['callerPn'], item['callerPnJid'], item['displayPeerJid'], item['peerJidAlt'], item['remoteJid'], item['peerJid']]
    candidates.any? { |value| normalize_number(value) == @contact_phone }
  end

  def normalize_number(value)
    value.to_s.split('@').first.to_s.gsub(/\D/, '')
  end

  def required_call_id(value)
    value.to_s.presence || raise(ConnectApi::Error, 'call_id é obrigatório.')
  end

  def response_call(response)
    data = response.respond_to?(:to_h) ? response.to_h.deep_stringify_keys : {}
    data = data['data'].deep_stringify_keys if data['data'].is_a?(Hash)
    data = data['call'].deep_stringify_keys if data['call'].is_a?(Hash)
    data
  end

  def merged_call(current_call, response)
    current_call.to_h.deep_stringify_keys.merge(response_call(response)).tap do |call|
      call['callId'] ||= current_call.to_h['callId'] || current_call.to_h['id']
      call['updatedAt'] ||= Time.current.utc.iso8601(3)
    end
  end

  def call_direction(call, fallback)
    direction = call.to_h.deep_stringify_keys['direction'].to_s.downcase
    return direction if %w[incoming outgoing].include?(direction)

    fallback
  end

  def sync_timeline_list(calls)
    return if @conversation.blank?

    calls.each { |call| sync_timeline(call, peer_phone: @contact_phone) }
  rescue StandardError => e
    Rails.logger.warn("[HUB Call Timeline] list sync failed: #{e.class}: #{e.message}")
  end

  def sync_timeline(call, **options)
    return if @conversation.blank?

    Whatsapp::ConnectApiCallTimelineSyncService.new(
      channel: @channel,
      conversation: @conversation
    ).sync(
      call,
      peer_name: @conversation.contact&.name,
      **options
    )
  rescue StandardError => e
    Rails.logger.warn("[HUB Call Timeline] sync failed: #{e.class}: #{e.message}")
  end

  def connect_api_public_url
    value = GlobalConfigService.load('CONNECT_API_PUBLIC_URL', ENV.fetch('CONNECT_API_PUBLIC_URL', '')).to_s.strip.sub(%r{/+$}, '')
    value = @client.base_url if value.blank?
    return value if value.start_with?('http://', 'https://')

    raise ConnectApi::Error, 'CONNECT_API_PUBLIC_URL deve apontar para a URL HTTPS pública do serviço para habilitar áudio no navegador.'
  end

  def websocket_url(public_url, media_path)
    uri = URI.parse(public_url)
    uri.scheme = uri.scheme == 'https' ? 'wss' : 'ws'
    uri.path = media_path.to_s.start_with?('/') ? media_path : "/#{media_path}"
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    raise ConnectApi::Error, 'CONNECT_API_PUBLIC_URL inválida.'
  end
end
