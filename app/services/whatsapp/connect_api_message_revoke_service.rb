# frozen_string_literal: true

require 'cgi'

class Whatsapp::ConnectApiMessageRevokeService
  class Error < StandardError; end

  def self.applicable?(message)
    channel = message&.conversation&.inbox&.channel
    return false unless channel.is_a?(Channel::Whatsapp)
    return false unless channel.provider == 'connectapi'
    return false if message.private?
    return false unless message.outgoing? || message.template?

    message.source_id.present?
  end

  def initialize(message:, client: nil)
    @message = message
    @channel = message.conversation.inbox.channel
    @config = @channel.provider_config.to_h.deep_stringify_keys
    @client = client
  end

  def perform!
    raise Error, 'Esta mensagem não pode ser apagada no WhatsApp.' unless self.class.applicable?(@message)

    key = provider_message_key
    raise Error, 'Não foi possível identificar a mensagem correspondente no WhatsApp.' if key['remoteJid'].blank?

    diagnostic = diagnostic_attributes(key)
    HubDiagnostics::Recorder.emit('message.revoke_started', diagnostic)

    from_me = key.key?('fromMe') ? ActiveModel::Type::Boolean.new.cast(key['fromMe']) : true
    raise Error, 'O WhatsApp informou que esta mensagem não foi enviada por esta conta.' unless from_me

    client.request(
      :delete,
      "/chat/deleteMessageForEveryone/#{CGI.escape(instance_name)}",
      body: {
        id: key['id'].presence || @message.source_id,
        fromMe: true,
        remoteJid: key['remoteJid'],
        participant: key['participant'].presence
      }.compact,
      timeout: 20
    )

    HubDiagnostics::Recorder.emit('message.revoke_finished', diagnostic.merge(success: true))
    true
  rescue ConnectApi::Error => error
    HubDiagnostics::Recorder.emit(
      'message.revoke_failed',
      diagnostic_attributes(provider_message_key_or_empty).merge(
        level: 'warn',
        http_status: error.status,
        reason: 'connect_api_rejected'
      ).compact
    )
    raise Error, revoke_error_message(error.status)
  rescue Error
    raise
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'message.revoke_failed',
      error,
      diagnostic_attributes(provider_message_key_or_empty).merge(reason: 'unexpected_error')
    )
    raise Error, 'Não foi possível apagar a mensagem no WhatsApp. Nada foi removido do HUB.'
  end

  private

  def provider_message_key
    @provider_message_key ||= native_message_key.presence || fallback_message_key
  end

  def provider_message_key_or_empty
    @provider_message_key || {}
  end

  def native_message_key
    response = client.request(
      :post,
      "/chat/findMessages/#{CGI.escape(instance_name)}",
      body: {
        where: { key: { id: @message.source_id.to_s } },
        page: 1,
        offset: 1
      },
      timeout: 10
    )

    record = first_record(response)
    return {} unless record.is_a?(Hash)

    key = record.deep_stringify_keys['key'].to_h.deep_stringify_keys
    {
      'id' => key['id'].to_s.presence || @message.source_id.to_s,
      'remoteJid' => key['remoteJid'].to_s.presence,
      'fromMe' => key.key?('fromMe') ? ActiveModel::Type::Boolean.new.cast(key['fromMe']) : nil,
      'participant' => key['participant'].to_s.presence
    }.compact
  rescue ConnectApi::Error => error
    # Lookup is an enrichment step. A missing persisted record must not prevent
    # revoke when HUB can derive the direct-chat JID from the conversation.
    HubDiagnostics::Recorder.emit(
      'message.revoke_lookup_failed',
      diagnostic_attributes({}).merge(level: 'warn', http_status: error.status)
    )
    {}
  end

  def first_record(response)
    data = response.respond_to?(:deep_stringify_keys) ? response.deep_stringify_keys : response
    return data.first if data.is_a?(Array)
    return unless data.is_a?(Hash)

    candidates = data['records'] || data['data'] || data['messages'] || data['rows']
    candidates.is_a?(Array) ? candidates.first : candidates
  end

  def fallback_message_key
    {
      'id' => @message.source_id.to_s,
      'fromMe' => true,
      'remoteJid' => fallback_remote_jid
    }.compact
  end

  def fallback_remote_jid
    aliases = Array(@message.conversation.contact.additional_attributes.to_h.dig('connect_api', 'aliases')).map(&:to_s)
    direct_alias = aliases.find { |value| value.match?(/@(s\.whatsapp\.net|c\.us)\z/i) }
    return direct_alias if direct_alias.present?

    source_id = @message.conversation.contact_inbox&.source_id.to_s
    return source_id if source_id.match?(/@(?:s\.whatsapp\.net|c\.us)\z/i)

    digits = source_id.sub(/\Awhatsapp:/i, '').gsub(/\D/, '')
    digits = @message.conversation.contact.phone_number.to_s.gsub(/\D/, '') if digits.blank?
    digits.present? ? "#{digits}@s.whatsapp.net" : nil
  end

  def client
    @client ||= if @config['connect_api_binding_mode'] == 'existing'
                  ConnectApi::BoundInstanceClient.new(api_key: @config['api_key'], timeout: 20)
                else
                  ConnectApi::Client.new(timeout: 20)
                end
  end

  def instance_name
    @config['instance_name'].to_s.strip.presence ||
      raise(Error, 'A caixa não possui uma instância Connect|API vinculada.')
  end

  def diagnostic_attributes(key)
    HubDiagnostics::Recorder.message_attributes(@message).merge(
      component: 'connectapi_message_revoke',
      channel_id: @channel.id,
      instance_name: @config['instance_name'].to_s.presence,
      source_id: @message.source_id,
      remote_jid_kind: jid_kind(key['remoteJid'])
    ).compact
  end

  def jid_kind(value)
    jid = value.to_s
    return 'phone' if jid.match?(/@(s\.whatsapp\.net|c\.us)\z/i)
    return 'group' if jid.end_with?('@g.us')
    return 'lid' if jid.end_with?('@lid')

    jid.present? ? 'other' : nil
  end

  def revoke_error_message(status)
    case status.to_i
    when 400, 404, 409, 422
      'O WhatsApp recusou a exclusão para todos. A mensagem foi mantida no HUB.'
    when 401, 403
      'A Connect|API recusou a autorização para apagar a mensagem. A mensagem foi mantida no HUB.'
    when 408, 504
      'A Connect|API demorou para confirmar a exclusão. A mensagem foi mantida no HUB para evitar divergência.'
    else
      'Não foi possível confirmar a exclusão no WhatsApp. A mensagem foi mantida no HUB.'
    end
  end
end
