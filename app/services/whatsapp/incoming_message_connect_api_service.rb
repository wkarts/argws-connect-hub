# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'tempfile'

# Connect|API exposes a generic Meta-compatible webhook, but HUB additionally
# reconciles each message with the native message repository when the webhook
# does not carry provider-specific direction/JID metadata. This keeps HUB
# correct without requiring a HUB-specific contract in Connect|API.
class Whatsapp::IncomingMessageConnectApiService < Whatsapp::IncomingMessageWhatsappCloudService
  MEDIA_LOOKUP_ATTEMPTS = 4
  MEDIA_LOOKUP_DELAYS = [0, 0.3, 0.8, 1.5].freeze
  MESSAGE_LOOKUP_DELAYS = [0, 0.15, 0.4, 0.8].freeze
  MEDIA_EXTENSIONS = {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    'video/mp4' => '.mp4',
    'audio/ogg' => '.ogg',
    'audio/ogg; codecs=opus' => '.ogg',
    'audio/mpeg' => '.mp3',
    'audio/mp4' => '.m4a',
    'application/pdf' => '.pdf'
  }.freeze

  private

  def processed_params
    value = super
    enrich_from_native_message!(value) unless @connect_api_message_enriched
    @connect_api_message_enriched = true
    value
  end

  def set_contact
    super
    return unless @contact

    refresh_connect_api_contact!
  end

  def set_conversation
    super
    return unless @conversation && @contact_inbox

    resolve_duplicate_active_conversations!
  end

  def create_message(message)
    super

    context = message[:connect_api].to_h.deep_stringify_keys
    return @message if context.blank?
    return @message unless ActiveModel::Type::Boolean.new.cast(context['from_me'])

    source = context['source'].to_s.strip.downcase.presence
    origin = source == 'api' ? 'bot' : 'external'

    @message.content_attributes = @message.content_attributes.to_h.merge(
      'connect_api_external_outgoing' => true,
      'connect_api_origin' => origin,
      'connect_api_source' => source,
      'connect_api_replied_outside_hub' => true
    ).compact

    @message
  end

  # Prefer the Meta-compatible descriptor when it is available. When that
  # descriptor cannot resolve the media (for example, storage/S3 is not being
  # used by the Connect|API instance), recover the original WhatsApp media from
  # the native generic endpoint using the persisted message record.
  def download_attachment_file(attachment_payload)
    media_id = attachment_payload[:id].to_s
    return if media_id.blank?

    graph_file = download_graph_media(media_id)
    return graph_file if graph_file.present?

    download_native_media(media_id, attachment_payload)
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] media recovery failed id=#{media_id}: #{e.class}: #{e.message}")
    nil
  end

  def download_graph_media(media_id)
    descriptor = nil
    MEDIA_LOOKUP_ATTEMPTS.times do |attempt|
      sleep(MEDIA_LOOKUP_DELAYS[attempt]) if MEDIA_LOOKUP_DELAYS[attempt].positive?
      descriptor = HTTParty.get(
        inbox.channel.media_url(media_id),
        headers: inbox.channel.api_headers,
        timeout: request_timeout
      )
      break if descriptor.success?
      break unless descriptor.code.to_i == 404
    end

    unless descriptor&.success?
      Rails.logger.warn(
        "[HUB Connect|API] media descriptor unavailable id=#{media_id} " \
        "status=#{descriptor&.code || 'n/a'} body=#{descriptor&.body.to_s.slice(0, 300)}"
      )
      return
    end

    media_url = descriptor.parsed_response.to_h.deep_stringify_keys['url'].to_s
    return if media_url.blank?

    Down.download(media_url)
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] Graph media download failed id=#{media_id}: #{e.class}: #{e.message}")
    nil
  end

  def download_native_media(media_id, attachment_payload)
    native_message = native_message_by_source_id(media_id)
    return if native_message.blank?

    response = HTTParty.post(
      "#{connect_api_base_url}/chat/getBase64FromMediaMessage/#{CGI.escape(instance_name)}",
      headers: native_headers,
      body: {
        message: native_message,
        convertToMp4: false
      }.to_json,
      timeout: request_timeout
    )

    unless response.success?
      Rails.logger.warn(
        "[HUB Connect|API] native media unavailable id=#{media_id} " \
        "status=#{response.code} body=#{response.body.to_s.slice(0, 300)}"
      )
      return
    end

    data = response.parsed_response
    data = data.deep_stringify_keys if data.respond_to?(:deep_stringify_keys)
    data = data['data'].deep_stringify_keys if data.is_a?(Hash) && data['data'].is_a?(Hash)
    return unless data.is_a?(Hash)

    encoded = data['base64'].to_s.strip
    return if encoded.blank?

    encoded = encoded.split(',', 2).last if encoded.start_with?('data:')
    binary = Base64.strict_decode64(encoded.gsub(/\s+/, ''))

    mimetype = data['mimetype'].to_s.presence || attachment_payload[:mime_type].to_s.presence || 'application/octet-stream'
    filename = File.basename(data['fileName'].to_s)
    filename = "#{media_id}#{extension_for(mimetype)}" if filename.blank?

    tempfile = Tempfile.new(['hub-connect-api-media-', File.extname(filename).presence || extension_for(mimetype)])
    tempfile.binmode
    tempfile.write(binary)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: mimetype
    )
  rescue ArgumentError => e
    Rails.logger.warn("[HUB Connect|API] invalid base64 media id=#{media_id}: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] native media download failed id=#{media_id}: #{e.class}: #{e.message}")
    nil
  end

  def extension_for(mimetype)
    normalized = mimetype.to_s.downcase
    MEDIA_EXTENSIONS[normalized] || MEDIA_EXTENSIONS[normalized.split(';', 2).first] || '.bin'
  end

  def enrich_from_native_message!(payload)
    message = payload&.dig(:messages)&.first
    return if message.blank? || message[:id].blank?

    existing_context = message[:connect_api].to_h.deep_stringify_keys
    if existing_context.key?('from_me')
      apply_existing_context!(payload, message, existing_context)
      return
    end

    native = native_message_by_source_id(message[:id])

    if native.present?
      native = native.deep_stringify_keys
      key = native['key'].to_h.deep_stringify_keys
      from_me = key.key?('fromMe') ? ActiveModel::Type::Boolean.new.cast(key['fromMe']) : nil
      source = native['source'].to_s.strip.presence
      peer = canonical_peer_phone(key)

      message[:connect_api] = existing_context.merge(
        'from_me' => from_me,
        'remote_jid' => key['remoteJid'],
        'remote_jid_alt' => key['remoteJidAlt'],
        'participant' => key['participant'],
        'participant_alt' => key['participantAlt'],
        'source' => source
      ).compact

      if peer.present?
        contact = payload[:contacts]&.first
        contact[:wa_id] = peer if contact.present?

        if contact.present? && meaningful_profile_name?(native['pushName'].to_s)
          contact[:profile] ||= {}
          current_name = contact.dig(:profile, :name).to_s
          contact[:profile][:name] = native['pushName'].to_s if current_name.blank? || generic_name_value?(current_name)
        end
      end

      message[:from] = from_me ? own_phone_number(payload) : peer if !from_me.nil? && (from_me || peer.present?)
      return
    end
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] native message reconciliation skipped: #{e.class}: #{e.message}")
  end

  def apply_existing_context!(payload, message, context)
    from_me = ActiveModel::Type::Boolean.new.cast(context['from_me'])
    peer = canonical_peer_phone(context)

    if peer.present? && payload[:contacts]&.first.present?
      payload[:contacts].first[:wa_id] = peer
    end

    message[:from] = from_me ? own_phone_number(payload) : peer if from_me || peer.present?
  end

  def native_message_by_source_id(source_id)
    source_id = source_id.to_s
    if @connect_api_native_message_source_id == source_id && @connect_api_native_message.present?
      return @connect_api_native_message
    end

    MESSAGE_LOOKUP_DELAYS.each do |delay_seconds|
      sleep(delay_seconds) if delay_seconds.positive?
      response = HTTParty.post(
        "#{connect_api_base_url}/chat/findMessages/#{CGI.escape(instance_name)}",
        headers: native_headers,
        body: {
          where: { key: { id: source_id } },
          page: 1,
          offset: 1
        }.to_json,
        timeout: request_timeout
      )
      next unless response.success?

      data = response.parsed_response
      data = data.deep_stringify_keys if data.respond_to?(:deep_stringify_keys)
      records = if data.is_a?(Array)
                  data
                elsif data.is_a?(Hash)
                  data.dig('messages', 'records') || data['records'] || data['data'] || []
                else
                  []
                end

      record = Array(records).first
      if record.present?
        @connect_api_native_message_source_id = source_id
        @connect_api_native_message = record
        return record
      end
    end

    nil
  rescue StandardError => e
    Rails.logger.debug("[HUB Connect|API] message lookup failed source_id=#{source_id}: #{e.class}: #{e.message}")
    nil
  end

  def canonical_peer_phone(values)
    values = values.to_h.deep_stringify_keys
    candidates = [
      values['remoteJidAlt'],
      values['remote_jid_alt'],
      values['remoteJid'],
      values['remote_jid'],
      values['participantAlt'],
      values['participant_alt'],
      values['participant'],
      values['senderPn'],
      values['sender']
    ].compact_blank.map(&:to_s).uniq

    phone_jid = candidates.find { |value| value.match?(/@(s\.whatsapp\.net|c\.us)\z/i) }
    candidate = phone_jid || candidates.find { |value| !value.match?(/@(lid|g\.us|broadcast)\z/i) }
    return if candidate.blank?

    digits = candidate.split('@', 2).first.gsub(/\D/, '')
    digits.presence
  end

  def own_phone_number(payload)
    payload.dig(:metadata, :display_phone_number).to_s.gsub(/\D/, '').presence ||
      inbox.channel.provider_config['phone_number_id'].to_s.gsub(/\D/, '').presence
  end

  def refresh_connect_api_contact!
    contact_params = @processed_params[:contacts]&.first
    return if contact_params.blank?

    profile_name = contact_params.dig(:profile, :name).to_s.strip
    profile_picture = contact_params.dig(:profile, :picture).to_s.strip
    message_context = @processed_params[:messages]&.first&.dig(:connect_api).to_h.deep_stringify_keys

    changes = {}
    changes[:name] = profile_name if meaningful_profile_name?(profile_name) && generic_contact_name?(@contact)

    current_additional = @contact.additional_attributes.to_h.deep_stringify_keys
    connect_api_attributes = current_additional.fetch('connect_api', {}).to_h.deep_stringify_keys
    aliases = [
      message_context['remote_jid'],
      message_context['remote_jid_alt'],
      message_context['participant'],
      message_context['participant_alt']
    ].compact_blank.uniq

    updated_connect_api = connect_api_attributes.merge(
      'aliases' => (Array(connect_api_attributes['aliases']) + aliases).compact_blank.uniq,
      'last_from_me' => ActiveModel::Type::Boolean.new.cast(message_context['from_me'])
    )
    updated_connect_api['profile_picture'] = profile_picture if profile_picture.present?

    changes[:additional_attributes] = current_additional.merge('connect_api' => updated_connect_api)
    @contact.update!(changes) if changes.present?

    return if profile_picture.blank?
    return if connect_api_attributes['profile_picture'] == profile_picture && @contact.avatar.attached?

    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_picture)
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] contact metadata refresh skipped: #{e.class}: #{e.message}")
  end

  def meaningful_profile_name?(name)
    return false if name.blank?

    digits = name.gsub(/\D/, '')
    digits.blank? || digits.length < 8
  end

  def generic_name_value?(name)
    name.to_s.match?(/\A\+?\d[\d\s().-]{7,}\z/)
  end

  def generic_contact_name?(contact)
    name = contact.name.to_s.strip
    return true if name.blank?

    name_digits = name.gsub(/\D/, '')
    phone_digits = contact.phone_number.to_s.gsub(/\D/, '')
    source_digits = @contact_inbox&.source_id.to_s.gsub(/\D/, '')

    [phone_digits, source_digits].compact_blank.include?(name_digits) || generic_name_value?(name)
  end

  def resolve_duplicate_active_conversations!
    active_scope = @contact_inbox.conversations.where.not(status: :resolved)
    duplicate_ids = active_scope.where.not(id: @conversation.id).pluck(:id)
    return if duplicate_ids.empty?

    Conversation.where(id: duplicate_ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: Conversation.statuses[:resolved],
      updated_at: Time.current
    )

    Rails.logger.info(
      "[HUB Connect|API] resolved duplicate active conversations contact_inbox=#{@contact_inbox.id} " \
      "kept=#{@conversation.id} resolved=#{duplicate_ids.join(',')}"
    )
  end

  def connect_api_base_url
    @connect_api_base_url ||= GlobalConfigService.load(
      'CONNECT_API_BASE_URL',
      ENV.fetch('CONNECT_API_BASE_URL', '')
    ).to_s.sub(%r{/+$}, '').tap do |value|
      raise 'CONNECT_API_BASE_URL is not configured' unless value.start_with?('http://', 'https://')
    end
  end

  def native_headers
    {
      'apikey' => GlobalConfigService.load(
        'CONNECT_API_AUTH_TOKEN',
        ENV.fetch('CONNECT_API_AUTH_TOKEN', '')
      ).to_s.strip,
      'Content-Type' => 'application/json'
    }
  end

  def instance_name
    inbox.channel.provider_config['instance_name'].to_s.strip
  end

  def request_timeout
    value = GlobalConfigService.load(
      'CONNECT_API_REQUEST_TIMEOUT',
      ENV.fetch('CONNECT_API_REQUEST_TIMEOUT', 60)
    ).to_i
    value.positive? ? value : 60
  end
end
