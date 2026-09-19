# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'digest'
require 'tempfile'

class Whatsapp::ConnectApiHistoricalReconciliationService
  STATUS_RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
  STATUS_MAP = {
    '2' => 'sent', 'SERVER_ACK' => 'sent',
    '3' => 'delivered', 'DELIVERY_ACK' => 'delivered',
    '4' => 'read', '5' => 'read', 'READ' => 'read', 'PLAYED' => 'read',
    '0' => 'failed', 'ERROR' => 'failed', 'DELETED' => 'deleted'
  }.freeze
  MEDIA_KEYS = {
    'imageMessage' => :image,
    'videoMessage' => :video,
    'audioMessage' => :audio,
    'documentMessage' => :file,
    'stickerMessage' => :image
  }.freeze
  WRAPPER_KEYS = %w[
    ephemeralMessage viewOnceMessage viewOnceMessageV2
    viewOnceMessageV2Extension documentWithCaptionMessage
  ].freeze

  Result = Struct.new(:result, :message, :conversation, keyword_init: true)

  def initialize(channel:, client:, operation_id: nil)
    @channel = channel
    @client = client
    @operation_id = operation_id
  end

  def process(raw_record)
    record = raw_record.to_h.deep_stringify_keys
    key = record['key'].to_h.deep_stringify_keys
    source_id = key['id'].to_s.presence || record['id'].to_s.presence
    return skipped('source_id_missing') if source_id.blank?
    return skipped('unsupported_group_or_broadcast', source_id: source_id) if ignored_jid?(key['remoteJid'])

    with_source_lock(source_id) do
      existing = find_message(source_id)
      return reconcile_existing(existing, record) if existing

      peer_phone = canonical_peer_phone(key)
      return skipped('peer_phone_unresolved', source_id: source_id) if peer_phone.blank?

      timestamp = timestamp_for(record)
      contact_inbox = find_or_create_contact_inbox(peer_phone, record, timestamp)
      conversation = historical_conversation(contact_inbox, timestamp)
      message = insert_message(record, key, source_id, timestamp, contact_inbox, conversation)
      attach_media(message, record) if message

      HubDiagnostics::Recorder.emit(
        'reconciliation.message_imported',
        diagnostic_context.merge(
          source_id: source_id,
          message_id: message&.id,
          conversation_id: conversation&.id,
          direction: key['fromMe'] ? 'outbound_external' : 'inbound'
        )
      )

      Result.new(result: 'created', message: message, conversation: conversation)
    end
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'reconciliation.record_failed',
      error,
      diagnostic_context.merge(source_id: raw_record.to_h.dig('key', 'id').to_s.presence)
    )
    raise
  end

  private

  def find_message(source_id)
    Message.find_by(
      account_id: @channel.account_id,
      inbox_id: @channel.inbox.id,
      source_id: source_id
    )
  end

  def reconcile_existing(message, record)
    status = native_status(record)
    if message.outgoing? && status.present?
      decision = HubDiagnostics::StatusPolicy.decision(message.status.to_s, status)
      if decision == :apply
        message.update_columns(status: Message.statuses.fetch(status), updated_at: message.updated_at)
        HubDiagnostics::Recorder.emit(
          'reconciliation.status_updated',
          diagnostic_context.merge(
            source_id: message.source_id,
            message_id: message.id,
            conversation_id: message.conversation_id,
            status: status
          )
        )
      end
    end

    attach_media(message, record) if message.attachments.empty? && media_descriptor(record).present?
    Result.new(result: 'existing', message: message, conversation: message.conversation)
  end

  def insert_message(record, key, source_id, timestamp, contact_inbox, conversation)
    from_me = ActiveModel::Type::Boolean.new.cast(key['fromMe'])
    content = text_body(record) || media_caption(record)
    status = if from_me
               native_status(record) || 'sent'
             else
               'sent'
             end

    content_attributes = {
      'connect_api_historical_reconciled' => true,
      'connect_api_origin' => from_me ? 'external' : 'provider',
      'connect_api_source' => record['source'].to_s.presence
    }.compact
    content_attributes['connect_api_external_outgoing'] = true if from_me
    content_attributes['is_unsupported'] = true if content.blank? && media_descriptor(record).blank?

    row = {
      content: content,
      account_id: @channel.account_id,
      inbox_id: @channel.inbox.id,
      conversation_id: conversation.id,
      message_type: Message.message_types.fetch(from_me ? 'outgoing' : 'incoming'),
      created_at: timestamp,
      updated_at: timestamp,
      private: false,
      status: Message.statuses.fetch(status),
      source_id: source_id,
      content_type: Message.content_types.fetch('text'),
      content_attributes: content_attributes,
      sender_type: from_me ? nil : 'Contact',
      sender_id: from_me ? nil : contact_inbox.contact_id,
      external_source_ids: {},
      additional_attributes: { 'connect_api_historical_reconciled' => true },
      processed_message_content: content,
      sentiment: {}
    }

    result = Message.insert_all!([row], returning: %w[id])
    message = Message.find(result.rows.first.first)
    advance_historical_conversation_activity(conversation, timestamp)
    message
  rescue ActiveRecord::RecordNotUnique
    find_message(source_id)
  end

  def find_or_create_contact_inbox(peer_phone, record, timestamp)
    source_id = peer_phone.to_s.gsub(/\D/, '')
    existing = ContactInbox.find_by(inbox_id: @channel.inbox.id, source_id: source_id)
    return existing if existing

    contact = Contact.find_by(account_id: @channel.account_id, phone_number: "+#{source_id}") ||
              insert_historical_contact(source_id, record, timestamp)

    result = ContactInbox.insert_all!(
      [{
        contact_id: contact.id,
        inbox_id: @channel.inbox.id,
        source_id: source_id,
        created_at: timestamp,
        updated_at: timestamp,
        hmac_verified: false
      }],
      returning: %w[id]
    )
    ContactInbox.find(result.rows.first.first)
  rescue ActiveRecord::RecordNotUnique
    ContactInbox.find_by!(inbox_id: @channel.inbox.id, source_id: source_id)
  end

  def insert_historical_contact(source_id, record, timestamp)
    name = record['pushName'].to_s.strip.presence || "+#{source_id}"
    result = Contact.insert_all!(
      [{
        account_id: @channel.account_id,
        name: name,
        phone_number: "+#{source_id}",
        created_at: timestamp,
        updated_at: timestamp,
        last_activity_at: timestamp,
        additional_attributes: {
          'connect_api_historical_import' => true,
          'connect_api_profile_picture' => record['profilePicUrl'].to_s.presence
        }.compact,
        custom_attributes: {},
        blocked: false,
        contact_type: Contact.contact_types.fetch('visitor'),
        middle_name: '',
        last_name: '',
        location: '',
        country_code: ''
      }],
      returning: %w[id]
    )
    Contact.find(result.rows.first.first)
  rescue ActiveRecord::RecordNotUnique
    Contact.find_by!(account_id: @channel.account_id, phone_number: "+#{source_id}")
  end

  def historical_conversation(contact_inbox, timestamp)
    scope = Conversation.where(
      account_id: @channel.account_id,
      inbox_id: @channel.inbox.id,
      contact_inbox_id: contact_inbox.id
    )

    candidate = scope.where('created_at <= ?', timestamp).order(created_at: :desc, id: :desc).first
    return candidate if candidate

    earliest = scope.order(created_at: :asc, id: :asc).first
    if historical_import_conversation?(earliest)
      earliest.update_columns(created_at: timestamp, updated_at: [earliest.updated_at, timestamp].min)
      return earliest
    end

    result = Conversation.insert_all!(
      [{
        account_id: @channel.account_id,
        inbox_id: @channel.inbox.id,
        status: Conversation.statuses.fetch('resolved'),
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        created_at: timestamp,
        updated_at: timestamp,
        last_activity_at: timestamp,
        additional_attributes: { 'connect_api_historical_import' => true },
        custom_attributes: {}
      }],
      returning: %w[id]
    )
    Conversation.find(result.rows.first.first)
  end

  def historical_import_conversation?(conversation)
    conversation&.additional_attributes.to_h['connect_api_historical_import'] == true
  end

  def advance_historical_conversation_activity(conversation, timestamp)
    return unless historical_import_conversation?(conversation)
    return unless timestamp > conversation.last_activity_at

    conversation.update_columns(last_activity_at: timestamp, updated_at: conversation.updated_at)
  end

  def attach_media(message, record)
    descriptor = media_descriptor(record)
    return unless descriptor

    file_type, media_node = descriptor
    uploaded = download_native_media(message.source_id, media_node)
    return unless uploaded

    attachment = message.attachments.build(
      account_id: message.account_id,
      file_type: file_type
    )
    attachment.file.attach(
      io: uploaded,
      filename: uploaded.original_filename,
      content_type: uploaded.content_type
    )
    attachment.save!
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'reconciliation.media_failed',
      error,
      diagnostic_context.merge(source_id: message.source_id, message_id: message.id)
    )
  end

  def download_native_media(media_id, media_node)
    response = @client.request(
      :post,
      "/chat/getBase64FromMediaMessage/#{CGI.escape(instance_name)}",
      body: { message: { key: { id: media_id } }, convertToMp4: false },
      timeout: 90
    )
    data = response.to_h.deep_stringify_keys
    data = data['data'].to_h.deep_stringify_keys if data['data'].is_a?(Hash)
    encoded = data['base64'].to_s.strip
    return if encoded.blank?

    encoded = encoded.split(',', 2).last if encoded.start_with?('data:')
    binary = Base64.strict_decode64(encoded.gsub(/\s+/, ''))
    max_bytes = ENV.fetch('CONNECT_API_MEDIA_MAX_BYTES', 40.megabytes).to_i
    return if max_bytes.positive? && binary.bytesize > max_bytes

    mimetype = [
      data['mimetype'], data['mimeType'], data['contentType'],
      media_node['mimetype'], media_node['mimeType']
    ].find { |value| value.to_s.include?('/') }.to_s.presence || 'application/octet-stream'
    filename = File.basename(data['fileName'].to_s.presence || media_node['fileName'].to_s.presence || '')
    filename = "#{media_id}.bin" if filename.blank?

    tempfile = Tempfile.new(['hub-connect-api-history-', File.extname(filename).presence || '.bin'])
    tempfile.binmode
    tempfile.write(binary)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: mimetype
    )
  end

  def text_body(record)
    message = unwrap_message(record.to_h.deep_stringify_keys['message'])
    return unless message.is_a?(Hash)

    message['conversation'].to_s.presence ||
      message.dig('extendedTextMessage', 'text').to_s.presence ||
      (record.to_h.deep_stringify_keys['messageType'].to_s == 'text' ? message['text'].to_s.presence : nil)
  end

  def media_caption(record)
    descriptor = media_descriptor(record)
    descriptor && descriptor.last['caption'].to_s.presence
  end

  def media_descriptor(record)
    message = unwrap_message(record.to_h.deep_stringify_keys['message'])
    return unless message.is_a?(Hash)

    MEDIA_KEYS.each do |key, type|
      node = message[key]
      return [type, node.to_h.deep_stringify_keys] if node.present?
    end
    nil
  end

  def unwrap_message(value)
    message = value.to_h.deep_stringify_keys
    loop do
      wrapper = WRAPPER_KEYS.find do |key|
        message[key].is_a?(Hash) && message[key]['message'].is_a?(Hash)
      end
      break unless wrapper

      message = message[wrapper]['message'].deep_stringify_keys
    end
    message
  end

  def native_status(record)
    values = Array(
      record.to_h.deep_stringify_keys['MessageUpdate'] ||
      record.to_h.deep_stringify_keys['messageUpdate'] ||
      record.to_h.deep_stringify_keys['messageUpdates']
    ).filter_map do |update|
      STATUS_MAP[update.to_h.deep_stringify_keys['status'].to_s.upcase]
    end

    return 'deleted' if values.include?('deleted')

    successes = values.select { |status| STATUS_RANK.key?(status) }
    return successes.max_by { |status| STATUS_RANK[status] } if successes.any?

    values.include?('failed') ? 'failed' : nil
  end

  def canonical_peer_phone(key)
    values = key.to_h.deep_stringify_keys
    candidates = [
      values['remoteJidAlt'], values['senderPn'], values['participantAlt'],
      values['remoteJid'], values['participant']
    ].compact_blank.map(&:to_s)

    phone_jid = candidates.find { |value| value.match?(/@(s\.whatsapp\.net|c\.us)\z/i) }
    candidate = phone_jid || candidates.find { |value| !value.match?(/@(lid|g\.us|broadcast)\z/i) }
    candidate&.split('@', 2)&.first.to_s.gsub(/\D/, '').presence
  end

  def ignored_jid?(value)
    value.to_s.end_with?('@g.us', '@broadcast')
  end

  def timestamp_for(record)
    value = record.to_h.deep_stringify_keys['messageTimestamp']
    numeric = value.is_a?(Hash) ? value.deep_stringify_keys['low'].to_i : value.to_i
    numeric /= 1000 if numeric > 10_000_000_000
    numeric.positive? ? Time.at(numeric).utc : Time.current.utc
  end

  def with_source_lock(source_id)
    key = Digest::SHA256.digest("hub:historical-reconcile:#{@channel.inbox.id}:#{source_id}").unpack1('q>')
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.select_value("SELECT pg_advisory_xact_lock(#{key})")
      yield
    end
  end

  def skipped(reason, source_id: nil)
    HubDiagnostics::Recorder.emit(
      'reconciliation.skipped',
      diagnostic_context.merge(reason: reason, source_id: source_id)
    )
    Result.new(result: 'skipped')
  end

  def diagnostic_context
    {
      component: 'connectapi_reconciliation',
      operation_id: @operation_id,
      account_id: @channel.account_id,
      inbox_id: @channel.inbox.id,
      channel_id: @channel.id,
      instance_name: instance_name,
      provider: @channel.provider_config.to_h['connect_api_provider']
    }.compact
  end

  def instance_name
    @channel.provider_config.to_h['instance_name'].to_s
  end
end
