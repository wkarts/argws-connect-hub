# frozen_string_literal: true

require 'base64'
require 'cgi'

class Whatsapp::Providers::ConnectApiService < Whatsapp::Providers::WhatsappCloudService
  DEFAULT_TIMEOUT = 60

  def validate_provider_config?
    Whatsapp::ConnectApiWebhookSetupService.new.perform(whatsapp_channel)
  end

  # Graph-compatible resources (templates/media descriptors) are scoped to the
  # Connect|API instance and therefore must use that instance token.
  def api_headers
    token = instance_token
    raise 'Connect|API instance token is not configured' if token.blank?

    {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json'
    }
  end

  # Regular text/media delivery uses the native Connect|API contract. Keep the
  # existing Graph-compatible interactive flow for input_select so this repair
  # does not regress lists/buttons already supported by HUB.
  def send_message(phone_number, message)
    return super if message.content_type == 'input_select'

    if message.attachments.present?
      send_native_attachment_message(phone_number, message)
    else
      send_native_text_message(phone_number, message)
    end
  end

  def send_template(message, phone_number, template_info)
    template = whatsapp_channel.opening_template_catalog.entries.find do |entry|
      entry['name'] == template_info[:name] && entry['language'] == template_info[:lang_code]
    end
    return super unless ConnectApi::LocalTemplateMessage.local?(template)

    send_local_template(message, phone_number, template)
  end

  def sync_templates
    Whatsapp::ConnectApiTemplateSyncService.new(whatsapp_channel).sync!
  rescue StandardError => e
    # Creation/background sync must not destroy the last successful catalog.
    # Explicit reconciliation uses sync! directly and reports errors to the UI.
    Rails.logger.warn("[HUB Connect|API] template sync skipped: #{e.class}: #{e.message}")
    whatsapp_channel.message_templates || []
  end

  private

  def send_local_template(message, phone_number, template)
    params = message.additional_attributes.to_h['template_params']
    local = ConnectApi::LocalTemplateMessage.new(template, params)
    local.validate_content!(message.content)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: { messaging_product: 'whatsapp', to: phone_number, type: 'template', template: local.payload }.to_json,
      timeout: request_timeout,
      follow_redirects: false
    )
    unless response.success?
      raise ConnectApi::LocalTemplateMessage::Error,
            "Não foi possível enviar o modelo (HTTP #{response.code}). Reconcilie os templates antes de tentar novamente."
    end

    data = response.parsed_response
    id = data.is_a?(Hash) && data['messages'].is_a?(Array) && data['messages'].first.is_a?(Hash) && data['messages'].first['id']
    unless id.is_a?(String) && !id.empty?
      raise ConnectApi::LocalTemplateMessage::Error, 'A API não confirmou o identificador da mensagem. Verifique a entrega antes de reenviar.'
    end

    message.update!(
      source_id: id,
      content_attributes: message.content_attributes.to_h.merge(
        'connect_api_template' => {
          'id' => template['id'], 'name' => template['name'], 'language' => template['language'],
          'version' => template['version'], 'source' => 'connectapi_local',
          'execution' => 'rendered_text', 'meta_approved' => false
        }
      )
    )
    id
  rescue ConnectApi::LocalTemplateMessage::Error => e
    message.update!(status: :failed, external_error: e.message)
    nil
  rescue StandardError => e
    # Do not retry a possibly delivered message or log credentials/response bodies.
    Rails.logger.warn("[HUB Connect|API] template delivery interrupted: #{e.class}")
    message.update!(status: :failed, external_error: 'Envio interrompido. Verifique a entrega antes de reenviar o modelo.')
    nil
  end

  def send_native_text_message(phone_number, message)
    response = HTTParty.post(
      native_endpoint('sendText'),
      headers: native_headers,
      body: {
        number: normalize_phone(phone_number),
        text: format_content(message)
      }.to_json,
      timeout: request_timeout
    )

    process_native_response(message, response)
  rescue StandardError => e
    process_native_exception(message, e)
  end

  def send_native_attachment_message(phone_number, message)
    attachment = message.attachments.first
    body, endpoint, media_key = native_attachment_payload(phone_number, message, attachment)

    response = post_native_attachment(endpoint, body)
    if !response.success? && attachment_file_available?(attachment)
      Rails.logger.warn(
        "[HUB Connect|API] media URL delivery failed; retrying as base64 " \
        "instance=#{instance_name} file_type=#{attachment.file_type}"
      )
      body[media_key] = Base64.strict_encode64(attachment.file.download)
      response = post_native_attachment(endpoint, body)
    end

    process_native_response(message, response)
  rescue StandardError => e
    process_native_exception(message, e)
  end

  def native_attachment_payload(phone_number, message, attachment)
    download_url = attachment.download_url
    body = { number: normalize_phone(phone_number) }

    if attachment.file_type == 'audio'
      body[:audio] = download_url
      return [body, 'sendWhatsAppAudio', :audio]
    end

    media_type = %w[image video].include?(attachment.file_type) ? attachment.file_type : 'document'
    body[:mediatype] = media_type
    body[:media] = download_url
    body[:caption] = message.content if message.content.present?
    if attachment_file_available?(attachment)
      body[:fileName] = attachment.file.filename.to_s if media_type == 'document'
      body[:mimetype] = attachment.file.content_type if attachment.file.content_type.present?
    end

    [body, 'sendMedia', :media]
  end

  def post_native_attachment(endpoint, body)
    HTTParty.post(
      native_endpoint(endpoint),
      headers: native_headers,
      body: body.compact.to_json,
      timeout: request_timeout
    )
  end

  def attachment_file_available?(attachment)
    attachment.respond_to?(:file) && attachment.file.respond_to?(:attached?) && attachment.file.attached?
  end

  def process_native_response(message, response)
    if response.success?
      message_id = extract_message_id(response.parsed_response)
      return message_id if message_id.present?

      Rails.logger.warn('[HUB Connect|API] send succeeded without a message id')
      return nil
    end

    error = response_error(response)
    Rails.logger.error("[HUB Connect|API] send failed: #{error}")
    message.update!(status: :failed, external_error: error)
    nil
  end

  def process_native_exception(message, error)
    safe_error = "#{error.class}: #{error.message}".slice(0, 1000)
    Rails.logger.error("[HUB Connect|API] send exception: #{safe_error}")
    message.update!(status: :failed, external_error: safe_error)
    nil
  rescue StandardError
    nil
  end

  def extract_message_id(payload)
    data = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : {}

    data.dig('key', 'id').presence ||
      data.dig('message', 'key', 'id').presence ||
      data.dig('data', 'key', 'id').presence ||
      data.dig('messages', 0, 'id').presence ||
      data['id'].presence
  end

  def response_error(response)
    parsed = response.parsed_response
    if parsed.is_a?(Hash)
      parsed = parsed.deep_stringify_keys
      return parsed.dig('error', 'message').to_s if parsed.dig('error', 'message').present?
      return parsed['message'].to_s if parsed['message'].present?
      return parsed['error'].to_s if parsed['error'].present?
    end

    response.body.to_s.presence || "HTTP #{response.code}"
  end

  def native_endpoint(action)
    "#{connect_api_base_url}/message/#{action}/#{CGI.escape(instance_name)}"
  end

  def native_headers
    {
      'apikey' => installation_token,
      'Content-Type' => 'application/json'
    }
  end

  def connect_api_base_url
    @connect_api_base_url ||= GlobalConfigService.load(
      'CONNECT_API_BASE_URL',
      ENV.fetch('CONNECT_API_BASE_URL', '')
    ).to_s.sub(%r{/+$}, '').tap do |value|
      raise 'CONNECT_API_BASE_URL is not configured' unless value.start_with?('http://', 'https://')
    end
  end

  def installation_token
    GlobalConfigService.load(
      'CONNECT_API_AUTH_TOKEN',
      ENV.fetch('CONNECT_API_AUTH_TOKEN', '')
    ).to_s.strip.presence || raise('CONNECT_API_AUTH_TOKEN is not configured')
  end

  def instance_token
    whatsapp_channel.provider_config['api_key'].to_s.strip.presence
  end

  def instance_name
    whatsapp_channel.provider_config['instance_name'].to_s.strip.presence ||
      raise('Connect|API instance name is not configured')
  end

  def request_timeout
    value = GlobalConfigService.load(
      'CONNECT_API_REQUEST_TIMEOUT',
      ENV.fetch('CONNECT_API_REQUEST_TIMEOUT', DEFAULT_TIMEOUT)
    ).to_i
    value.positive? ? value : DEFAULT_TIMEOUT
  end

  def normalize_phone(value)
    value.to_s.gsub(/\D/, '')
  end
end
