# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'tempfile'

class Channels::Whatsapp::ConnectApiMediaSyncJob < ApplicationJob
  queue_as :low

  DEFAULT_MAX_RECORDS = 80
  MAX_RECORDS = DEFAULT_MAX_RECORDS
  DEFAULT_MESSAGE_RECOVERY_LOOKBACK_SECONDS = 6.hours.to_i
  DEFAULT_HTTP_TIMEOUT_SECONDS = 15
  DEFAULT_MAX_RUNTIME_SECONDS = 25
  LOOKBACK = 48.hours
  STATUS_RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
  STATUS_MAP = {
    '2' => 'sent', 'SERVER_ACK' => 'sent',
    '3' => 'delivered', 'DELIVERY_ACK' => 'delivered',
    '4' => 'read', '5' => 'read', 'READ' => 'read', 'PLAYED' => 'read',
    '0' => 'failed', 'ERROR' => 'failed', 'DELETED' => 'deleted'
  }.freeze
  MEDIA_KEYS = {
    'imageMessage' => 'image',
    'videoMessage' => 'video',
    'audioMessage' => 'audio',
    'documentMessage' => 'document',
    'stickerMessage' => 'image'
  }.freeze
  WRAPPER_KEYS = %w[ephemeralMessage viewOnceMessage viewOnceMessageV2 viewOnceMessageV2Extension documentWithCaptionMessage].freeze
  EXTENSIONS = {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    'video/mp4' => '.mp4',
    'audio/ogg' => '.ogg',
    'audio/mpeg' => '.mp3',
    'audio/mp4' => '.m4a',
    'application/pdf' => '.pdf'
  }.freeze

  def perform(channel_id)
    @channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return unless @channel&.inbox
    return if manual_instance_deletion?
    return if instance_name.blank?

    context = diagnostic_context
    records = recent_native_messages.sort_by { |record| timestamp_for(record) }
    processed = 0
    skipped = 0
    HubDiagnostics::Recorder.emit(
      'sync.background_started',
      context.merge(records_found: records.length)
    )

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_runtime_seconds

    records.each do |record|
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      begin
        sync_record(record)
        processed += 1
      rescue StandardError => e
        skipped += 1
        Rails.logger.warn(
          "[HUB Connect|API] reliability sync record failed channel=#{@channel.id} " \
          "message=#{message_id(record)}: #{e.class}: #{e.message}"
        )
        HubDiagnostics::Recorder.error(
          'sync.record_failed',
          e,
          context.merge(source_id: message_id(record))
        )
      end
    end

    HubDiagnostics::Recorder.emit(
      'sync.background_finished',
      context.merge(records_found: records.length, records_processed: processed, records_skipped: skipped)
    )
  rescue ConnectApi::Error => e
    HubDiagnostics::Recorder.error(
      'sync.background_failed',
      e,
      { component: 'connectapi_sync', channel_id: channel_id }
    )
    Rails.logger.warn("[HUB Connect|API] reliability sync failed channel=#{channel_id}: #{e.message}")
    raise if e.status.to_i >= 500 || e.status.to_i == 0
  end

  private

  def recent_native_messages
    response = client.request(
      :post,
      "/chat/findMessages/#{CGI.escape(instance_name)}",
      body: { page: 1, offset: max_records },
      timeout: recovery_http_timeout
    )
    records = extract_records(response)
    records.select do |record|
      stamp = timestamp_for(record)
      media_recent = media_descriptor(record).present? && stamp >= LOOKBACK.ago.to_i
      message_recent = (text_body(record).present? || native_status(record).present?) &&
                       stamp >= message_recovery_lookback.ago.to_i
      media_recent || message_recent
    end
  end

  def max_records
    ENV.fetch('HUB_CONNECT_RECOVERY_MAX_RECORDS', DEFAULT_MAX_RECORDS).to_i.clamp(20, 200)
  end

  def message_recovery_lookback
    seconds = ENV.fetch(
      'HUB_CONNECT_RECOVERY_LOOKBACK_SECONDS',
      DEFAULT_MESSAGE_RECOVERY_LOOKBACK_SECONDS
    ).to_i.clamp(300, 86_400)

    seconds.seconds
  end

  def recovery_http_timeout
    ENV.fetch(
      'HUB_CONNECT_RECOVERY_HTTP_TIMEOUT_SECONDS',
      DEFAULT_HTTP_TIMEOUT_SECONDS
    ).to_i.clamp(3, 30)
  end

  def max_runtime_seconds
    ENV.fetch(
      'HUB_CONNECT_RECOVERY_MAX_RUNTIME_SECONDS',
      DEFAULT_MAX_RUNTIME_SECONDS
    ).to_i.clamp(5, 60)
  end

  def extract_records(value)
    return value if value.is_a?(Array)
    return [] unless value.is_a?(Hash)

    data = value.deep_stringify_keys
    Array(data.dig('messages', 'records') || data['records'] || data['data'])
  end

  def sync_record(raw_record)
    record = raw_record.to_h.deep_stringify_keys
    key = record['key'].to_h.deep_stringify_keys
    id = key['id'].to_s.presence || record['id'].to_s.presence
    return if id.blank?
    return if ignored_jid?(key['remoteJid'])

    existing = Message.find_by(account_id: @channel.account_id, inbox_id: @channel.inbox.id, source_id: id)
    body = text_body(record)
    media_type, media_node = media_descriptor(record)

    if existing.blank?
      if body.present?
        existing = recover_text_message(record, key, id, body)
      elsif media_type && media_node
        existing = recover_media_message(record, key, id, media_type, media_node)
      end
    elsif media_type && media_node && existing.attachments.empty?
      recover_existing_attachment(existing, media_type, media_node)
    end

    reconcile_native_status(record, existing) if existing
  end

  def recover_text_message(record, key, id, body)
    peer_phone = canonical_peer_phone(key)
    unless peer_phone.present?
      HubDiagnostics::Recorder.emit(
        'sync.skipped',
        diagnostic_context.merge(source_id: id, reason: 'peer_phone_unresolved')
      )
      return
    end

    from_me = ActiveModel::Type::Boolean.new.cast(key['fromMe'])
    payload = synthetic_webhook(record, key, id, peer_phone, from_me, 'text', {})
    payload[:entry].first[:changes].first[:value][:messages].first[:text] = { body: body }

    incoming_service.new(inbox: @channel.inbox, params: payload.with_indifferent_access).perform

    message = Message.find_by(account_id: @channel.account_id, inbox_id: @channel.inbox.id, source_id: id)
    HubDiagnostics::Recorder.emit(
      'sync.text_processed',
      diagnostic_context.merge(source_id: id, from_me: from_me, success: message.present?)
    )
    message
  end

  def recover_media_message(record, key, id, media_type, media_node)
    peer_phone = canonical_peer_phone(key)
    return unless peer_phone.present?

    from_me = ActiveModel::Type::Boolean.new.cast(key['fromMe'])
    payload = synthetic_webhook(record, key, id, peer_phone, from_me, media_type, media_node)
    incoming_service.new(inbox: @channel.inbox, params: payload.with_indifferent_access).perform

    message = Message.find_by(account_id: @channel.account_id, inbox_id: @channel.inbox.id, source_id: id)
    recover_existing_attachment(message, media_type, media_node) if message && message.attachments.empty?
    message
  end

  def reconcile_native_status(record, message)
    return unless message.outgoing?

    status = native_status(record)
    return if status.blank?

    decision = HubDiagnostics::StatusPolicy.decision(message.status.to_s, status)
    return unless decision == :apply

    payload = {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            messaging_product: 'whatsapp',
            metadata: {
              display_phone_number: @channel.phone_number.to_s.gsub(/\D/, ''),
              phone_number_id: @channel.provider_config.to_h['phone_number_id'].to_s
            },
            statuses: [{
              id: message.source_id,
              status: status,
              timestamp: timestamp_for(record).to_s
            }]
          }
        }]
      }]
    }

    incoming_service.new(inbox: @channel.inbox, params: payload.with_indifferent_access).perform
    HubDiagnostics::Recorder.emit(
      'sync.status_processed',
      diagnostic_context.merge(source_id: message.source_id, message_id: message.id, status: status)
    )
  end

  def incoming_service
    Whatsapp::IncomingMessageConnectApiStatusAwareService
  end

  def recover_existing_attachment(message, media_type, media_node)
    uploaded = download_native_media(message.source_id, media_node)
    return unless uploaded

    attachment = message.attachments.build(
      account_id: message.account_id,
      file_type: attachment_file_type(media_type)
    )
    attachment.file.attach(
      io: uploaded,
      filename: uploaded.original_filename,
      content_type: uploaded.content_type
    )
    attachment.save!

    caption = media_node['caption'].to_s.presence
    message.update!(content: caption) if message.content.blank? && caption.present?
    message.touch
    Rails.logger.info("[HUB Connect|API] recovered missing media message=#{message.id} source_id=#{message.source_id}")
  end

  # /chat/findMessages intentionally returns a sanitized representation of
  # media messages. Passing that representation back to the media endpoint
  # removes the native media key/url information needed by both Baileys and
  # ZAPO. Send only key.id so Connect|API resolves the raw stored message.
  def download_native_media(media_id, media_node)
    response = client.request(
      :post,
      "/chat/getBase64FromMediaMessage/#{CGI.escape(instance_name)}",
      body: { message: { key: { id: media_id } }, convertToMp4: false },
      timeout: 90
    )
    data = response.respond_to?(:deep_stringify_keys) ? response.deep_stringify_keys : {}
    data = data['data'].deep_stringify_keys if data['data'].is_a?(Hash)

    encoded = data['base64'].to_s.strip
    return if encoded.blank?

    encoded = encoded.split(',', 2).last if encoded.start_with?('data:')
    binary = Base64.strict_decode64(encoded.gsub(/\s+/, ''))
    max_bytes = ENV.fetch('CONNECT_API_MEDIA_MAX_BYTES', 40.megabytes).to_i
    raise ConnectApi::Error, "Mídia excede limite do HUB (#{binary.bytesize} bytes)." if max_bytes.positive? && binary.bytesize > max_bytes

    mimetype = native_media_mimetype(data, media_node)
    filename = File.basename(data['fileName'].to_s.presence || media_node['fileName'].to_s.presence || '')
    filename = "#{media_id}#{extension_for(mimetype)}" if filename.blank?

    tempfile = Tempfile.new(['hub-connect-api-media-sync-', File.extname(filename).presence || extension_for(mimetype)])
    tempfile.binmode
    tempfile.write(binary)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: mimetype)
  rescue ArgumentError => e
    Rails.logger.warn("[HUB Connect|API] invalid native media base64 id=#{media_id}: #{e.message}")
    nil
  end

  def native_media_mimetype(data, media_node)
    candidates = [data['mimetype'], data['mimeType'], data['contentType'], media_node['mimetype'], media_node['mimeType']]
    candidates.each do |candidate|
      value = candidate.to_s.strip
      return value if value.include?('/')
    end

    'application/octet-stream'
  end

  def synthetic_webhook(record, key, id, peer_phone, from_me, media_type, media_node)
    own_phone = @channel.provider_config.to_h['phone_number_id'].to_s.gsub(/\D/, '').presence ||
                @channel.phone_number.to_s.gsub(/\D/, '')
    attachment = {
      id: id,
      mime_type: media_node['mimetype'].presence || media_node['mimeType'].presence || 'application/octet-stream'
    }
    attachment[:caption] = media_node['caption'] if media_node['caption'].present?
    attachment[:filename] = media_node['fileName'] if media_node['fileName'].present?

    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            messaging_product: 'whatsapp',
            metadata: { display_phone_number: own_phone, phone_number_id: own_phone },
            contacts: [{ profile: { name: record['pushName'].to_s.presence || peer_phone }, wa_id: peer_phone }],
            messages: [{
              from: from_me ? own_phone : peer_phone,
              id: id,
              timestamp: timestamp_for(record).to_s,
              type: media_type,
              media_type => attachment,
              connect_api: {
                from_me: from_me,
                remote_jid: key['remoteJid'],
                remote_jid_alt: key['remoteJidAlt'],
                participant: key['participant'],
                participant_alt: key['participantAlt'],
                source: record['source'],
                recovered: true
              }.compact,
              context: native_reply_context(record)
            }]
          }
        }]
      }]
    }
  end

  def native_reply_context(record)
    context = find_native_context_info(record.to_h.deep_stringify_keys['message'])
    stanza_id = context.to_h.deep_stringify_keys['stanzaId'].to_s.presence ||
                context.to_h.deep_stringify_keys['stanza_id'].to_s.presence
    stanza_id ? { id: stanza_id } : nil
  end

  def find_native_context_info(value)
    return {} unless value.is_a?(Hash)

    hash = value.deep_stringify_keys
    return hash['contextInfo'] if hash['contextInfo'].is_a?(Hash)

    hash.each_value do |child|
      next unless child.is_a?(Hash)

      found = find_native_context_info(child)
      return found if found.present?
    end

    {}
  end

  def text_body(record)
    message = unwrap_message(record.to_h.deep_stringify_keys['message'])
    return unless message.is_a?(Hash)

    message['conversation'].to_s.presence ||
      message.dig('extendedTextMessage', 'text').to_s.presence ||
      (record.to_h.deep_stringify_keys['messageType'].to_s == 'text' ? message['text'].to_s.presence : nil)
  end

  def native_status(record)
    values = Array(
      record.to_h.deep_stringify_keys['MessageUpdate'] ||
      record.to_h.deep_stringify_keys['messageUpdate'] ||
      record.to_h.deep_stringify_keys['messageUpdates']
    ).filter_map do |update|
      raw = update.to_h.deep_stringify_keys['status'].to_s.upcase
      STATUS_MAP[raw]
    end

    return 'deleted' if values.include?('deleted')

    successes = values.select { |status| STATUS_RANK.key?(status) }
    return successes.max_by { |status| STATUS_RANK[status] } if successes.any?

    values.include?('failed') ? 'failed' : nil
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
      wrapper = WRAPPER_KEYS.find { |key| message[key].is_a?(Hash) && message[key]['message'].is_a?(Hash) }
      break unless wrapper

      message = message[wrapper]['message'].deep_stringify_keys
    end
    message
  end

  def canonical_peer_phone(key)
    values = key.to_h.deep_stringify_keys
    candidates = [values['remoteJidAlt'], values['senderPn'], values['participantAlt'], values['remoteJid'], values['participant']].compact_blank
    phone_jid = candidates.find { |value| value.to_s.match?(/@(s\.whatsapp\.net|c\.us)\z/i) }
    candidate = phone_jid || candidates.find { |value| !value.to_s.match?(/@(lid|g\.us|broadcast)\z/i) }
    return if candidate.blank?

    candidate.to_s.split('@', 2).first.gsub(/\D/, '').presence
  end

  def ignored_jid?(value)
    value.to_s.end_with?('@g.us', '@broadcast')
  end

  def timestamp_for(record)
    value = record.to_h.deep_stringify_keys['messageTimestamp']
    numeric = if value.is_a?(Hash)
                value.deep_stringify_keys['low'].to_i
              elsif value.respond_to?(:to_i)
                value.to_i
              else
                0
              end
    numeric.positive? ? numeric : Time.current.to_i
  end

  def message_id(record)
    record.to_h.deep_stringify_keys.dig('key', 'id').to_s
  end

  def attachment_file_type(media_type)
    { 'image' => :image, 'video' => :video, 'audio' => :audio, 'document' => :file }.fetch(media_type, :file)
  end

  def extension_for(mimetype)
    normalized = mimetype.to_s.downcase
    EXTENSIONS[normalized] || EXTENSIONS[normalized.split(';', 2).first] || '.bin'
  end

  def diagnostic_context
    config = @channel.provider_config.to_h
    {
      component: 'connectapi_sync',
      account_id: @channel.account_id,
      inbox_id: @channel.inbox&.id,
      channel_id: @channel.id,
      instance_name: config['instance_name'],
      provider: config['connect_api_provider']
    }.compact
  end

  def manual_instance_deletion?
    ActiveModel::Type::Boolean.new.cast(@channel.provider_config.to_h['connect_api_manual_deletion'])
  end

  def instance_name
    @channel.provider_config.to_h['instance_name'].to_s.strip
  end

  def client
    if @channel.provider_config.to_h['connect_api_binding_mode'] == 'existing'
      return @client ||= ConnectApi::BoundInstanceClient.new(api_key: @channel.provider_config.to_h['api_key'])
    end

    @client ||= ConnectApi::Client.new
  end
end
