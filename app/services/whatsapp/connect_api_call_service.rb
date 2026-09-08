# frozen_string_literal: true

require 'uri'

class Whatsapp::ConnectApiCallService
  CALL_PROVIDER = 'WHATSAPP-ZAPO'

  def initialize(whatsapp_channel:, contact_phone: nil, client: ConnectApi::Client.new)
    @channel = whatsapp_channel
    @contact_phone = normalize_number(contact_phone)
    @client = client
  end

  def capabilities
    provider = current_provider
    {
      provider: provider,
      calls: provider == CALL_PROVIDER,
      voice: provider == CALL_PROVIDER,
      video: false
    }
  end

  def list
    ensure_call_provider!
    calls = @client.list_calls(instance_name)
    return calls if @contact_phone.blank?

    calls.select { |call| call_matches_contact?(call) }
  end

  def offer(number:, is_video: false, call_duration: nil)
    ensure_call_provider!
    raise ConnectApi::Error, 'Chamadas de vídeo ainda não estão disponíveis neste provider.' if ActiveModel::Type::Boolean.new.cast(is_video)

    digits = number.to_s.gsub(/\D/, '')
    raise ConnectApi::Error, 'O contato não possui telefone válido para chamada.' if digits.blank?

    @client.offer_call(instance_name, number: digits, is_video: false, call_duration: call_duration)
  end

  def accept(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    ensure_call_for_contact!(call_id)
    @client.accept_call(instance_name, call_id)
  end

  def reject(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    ensure_call_for_contact!(call_id)
    @client.reject_call(instance_name, call_id)
  end

  def end_call(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    ensure_call_for_contact!(call_id)
    @client.end_call(instance_name, call_id)
  end

  def mute(call_id, muted:)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    ensure_call_for_contact!(call_id)
    @client.mute_call(instance_name, call_id, muted: muted)
  end

  def media_ticket(call_id)
    ensure_call_provider!
    call_id = required_call_id(call_id)
    ensure_call_for_contact!(call_id)
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

  def instance_name
    @instance_name ||= @channel.provider_config.to_h['instance_name'].to_s.presence || raise(ConnectApi::Error, 'Instância Connect|API não provisionada.')
  end

  def current_provider
    configured = @channel.provider_config.to_h['connect_api_provider'].to_s
    return configured if configured.present?

    instance = @client.fetch_instances.find do |item|
      item = item.to_h
      (item['name'] || item['instanceName']).to_s == instance_name
    end
    (instance&.dig('integration') || instance&.dig('provider') || 'WHATSAPP-BAILEYS').to_s
  rescue ConnectApi::Error
    @channel.provider_config.to_h['connect_api_provider'].to_s.presence || 'WHATSAPP-BAILEYS'
  end

  def ensure_call_provider!
    return if current_provider == CALL_PROVIDER

    raise ConnectApi::Error, 'Esta instância usa um provider sem chamadas. Migre-a para WHATSAPP-ZAPO no HUB Admin ou crie a caixa usando ZAPO.'
  end

  def ensure_call_for_contact!(call_id)
    return if @contact_phone.blank?

    call = @client.list_calls(instance_name).find do |item|
      id = item.to_h['callId'] || item.to_h['id']
      id.to_s == call_id.to_s
    end
    raise ConnectApi::Error, 'Chamada não encontrada nesta conversa.' unless call && call_matches_contact?(call)
  end

  def call_matches_contact?(call)
    return true if @contact_phone.blank?

    item = call.to_h.deep_stringify_keys
    candidates = [item['number'], item['callerPn'], item['displayPeerJid'], item['peerJid']]
    candidates.any? { |value| normalize_number(value) == @contact_phone }
  end

  def normalize_number(value)
    value.to_s.split('@').first.to_s.gsub(/\D/, '')
  end

  def required_call_id(value)
    value.to_s.presence || raise(ConnectApi::Error, 'call_id é obrigatório.')
  end

  def connect_api_public_url
    value = GlobalConfigService.load('CONNECT_API_PUBLIC_URL', ENV.fetch('CONNECT_API_PUBLIC_URL', '')).to_s.strip.sub(%r{/+$}, '')
    value = @client.base_url if value.blank?
    return value if value.start_with?('http://', 'https://')

    raise ConnectApi::Error, 'CONNECT_API_PUBLIC_URL deve apontar para a URL HTTPS pública da Connect|API para habilitar áudio no navegador.'
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
