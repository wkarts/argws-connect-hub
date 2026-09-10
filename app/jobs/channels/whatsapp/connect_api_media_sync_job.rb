# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'tempfile'

class Channels::Whatsapp::ConnectApiMediaSyncJob < ApplicationJob
  queue_as :low

  MAX_RECORDS = 80
  LOOKBACK = 48.hours
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

    recent_native_messages.sort_by { |record| timestamp_for(record) }.each do |record|
      sync_record(record)
    rescue StandardError => e
      Rails.logger.warn(
        "[HUB Connect|API] media sync record failed channel=#{@channel.id} " \
        "message=#{message_id(record)}: #{e.class}: #{e.message}"
      )
    end
  rescue ConnectApi::Error => e
    Rails.logger.warn("[HUB Connect|API] media sync failed channel=#{channel_id}: #{e.message}")
    raise if e.status.to_i >= 500 || e.status.to_i == 0
  end

  private

  def recent_native_messages
    response = client.request(
      :post,
      "/chat/findMessages/#{CGI.escape(instance_name)}",
      body: { page: 1, offset: MAX_RECORDS }
    )
    records = extract_records(response)
    records.select do |record|
      media_descriptor(record).present? && timestamp_for(record) >= LOOKBACK.ago.to_i
    end
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

    media_type, media_node = media_descriptor(record)
    return unless media_type && media_node

    existing = Message.find_by(inbox_id: @channel.inbox.id, source_id: id)
    if existing
      recover_existing_attachment(existing, record, media_type, media_node) if existing.attachments.empty?
      return
    end

    peer_phone = canonical_peer_phone(key)
    return if peer_phone.blank?

    from_me = ActiveModel::Type::Boolean.new.cast(key['fromMe'])
    payload = synthetic_webhook(record, key, id, peer_phone, from_me, media_type, media_node)
    Whatsapp::IncomingMessageConnectApiService.new(inbox: @channel.inbox, params: payload.with_indifferent_access).perform

    # The synthetic webhook still tries the normal Graph media path first. If
    # that path is unavailable, repair the just-created message in the same run
    # instead of waiting for the next one-minute reconciliation cycle.
    created = Message.find_by(inbox_id: @channel.inbox.id, source_id: id)
    recover_existing_attachment(created, record, media_type, media_node) if created && created.attachments.empty?
  end

  def recover_existing_attachment(message, record, media_type, media_node)
    uploaded = download_native_media(record, message.source_id, media_node)
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

  def download_native_media(record, media_id, media_node)
    response = client.request(
      :post,
      "/chat/getBase64FromMediaMessage/#{CGI.escape(instance_name)}",
      body: { message: record, convertToMp4: false },
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

    mimetype = data['mimetype'].to_s.presence || media_node['mimetype'].to_s.presence || media_node['mimeType'].to_s.presence || 'application/octet-stream'
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

  def synthetic_webhook(record, key, id, peer_phone, from_me, media_type, media_node)
    own_phone = @channel.provider_config.to_h['phone_number_id'].to_s.gsub(/\D/, '').presence || @channel.phone_number.to_s.gsub(/\D/, '')
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
                source: record['source']
              }.compact
            }]
          }
        }]
      }]
    }
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

  def manual_instance_deletion?
    ActiveModel::Type::Boolean.new.cast(@channel.provider_config.to_h['connect_api_manual_deletion'])
  end

  def instance_name
    @channel.provider_config.to_h['instance_name'].to_s.strip
  end

  def client
    @client ||= ConnectApi::Client.new
  end
end
