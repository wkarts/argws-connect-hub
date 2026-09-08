# frozen_string_literal: true

require 'cgi'

class Whatsapp::ConnectApiWebhookSetupService
  DEFAULT_TIMEOUT = 60
  DEFAULT_PROVIDER = 'WHATSAPP-BAILEYS'
  SUPPORTED_PROVIDERS = %w[WHATSAPP-BAILEYS WHATSAPP-ZAPO].freeze

  def perform(whatsapp_channel)
    @channel = whatsapp_channel
    normalize_config!
    ensure_instance!
    sync_instance_metadata!
    enable_meta_compatibility!

    if config['disconnect']
      disconnect!
    elsif config['connect'] || !config['provisioned']
      connect!
    else
      refresh_status!
    end

    config.delete('connect')
    config.delete('disconnect')
    persist_config!
    true
  rescue StandardError => e
    Rails.logger.error("[HUB Connect|API] #{e.class}: #{e.message}")
    whatsapp_channel.errors.add(:provider_config, "Connect|API: #{e.message}")
    false
  end

  private

  attr_reader :channel

  def config
    @config ||= channel.provider_config.deep_stringify_keys
  end

  def normalize_config!
    digits = channel.phone_number.to_s.gsub(/\D/, '')
    raise 'phone number is required' if digits.blank?

    config['phone_number'] = channel.phone_number
    config['phone_number_id'] = digits
    config['business_account_id'] = digits
    config['instance_name'] ||= "hub-#{channel.account_id}-#{digits}"
    config['api_key'] ||= SecureRandom.hex(32)
    config['auth_mode'] = %w[qrcode pairing_code].include?(config['auth_mode']) ? config['auth_mode'] : 'qrcode'
    requested_provider = config['connect_api_provider'].presence || GlobalConfigService.load('CONNECT_API_DEFAULT_PROVIDER', ENV.fetch('CONNECT_API_DEFAULT_PROVIDER', DEFAULT_PROVIDER)).to_s
    config['connect_api_provider'] = SUPPORTED_PROVIDERS.include?(requested_provider) ? requested_provider : DEFAULT_PROVIDER
    config['calls_supported'] = config['connect_api_provider'] == 'WHATSAPP-ZAPO'
    config['voice_supported'] = config['calls_supported']
    config['url'] = "#{base_url}/graph"
  end

  def ensure_instance!
    return if instance_accessible?

    body = {
      instanceName: config['instance_name'],
      token: config['api_key'],
      integration: config['connect_api_provider'],
      qrcode: false,
      # Storing the stable number lets the Meta-compatible identity resolver work
      # before the device session has completed authentication.
      number: config['phone_number_id'],
      groupsIgnore: config.fetch('ignore_group_messages', true),
      syncFullHistory: !config.fetch('ignore_history_messages', true)
    }
    if config['connect_api_provider'] == 'WHATSAPP-ZAPO' && config['voip_max_concurrent_calls'].present?
      body[:voipMaxConcurrentCalls] = config['voip_max_concurrent_calls'].to_i
    end

    response = HTTParty.post(
      "#{base_url}/instance/create",
      headers: admin_headers,
      body: body.to_json,
      timeout: request_timeout
    )

    unless response.success?
      # A persisted instance may already exist after a HUB restart. Verify using
      # the per-instance credential before treating create conflict as failure.
      raise response_body(response) unless instance_accessible?
    end

    config['provisioned'] = true
    persist_config!
  end

  def enable_meta_compatibility!
    webhook_url = "#{ENV.fetch('FRONTEND_URL', '').sub(%r{/$}, '')}/webhooks/whatsapp/#{config['phone_number_id']}"
    raise 'FRONTEND_URL must be configured with an absolute public URL' unless webhook_url.start_with?('http://', 'https://')

    response = HTTParty.put(
      "#{base_url}/compat/meta/#{CGI.escape(config['instance_name'])}",
      headers: instance_headers,
      body: { enabled: true, webhookUrl: webhook_url }.to_json,
      timeout: request_timeout
    )
    raise response_body(response) unless response.success?

    data = response.parsed_response || {}
    config['meta_compatible'] = true
    config['graph_url'] = data['graphUrl'] || "#{base_url}/graph"
    config['url'] = config['graph_url']
    config['phone_number_id'] = data['phoneNumberId'].to_s if data['phoneNumberId'].present?
    config['business_account_id'] = data['businessAccountId'].to_s if data['businessAccountId'].present?
    config['display_phone_number'] = data['displayPhoneNumber'].to_s if data['displayPhoneNumber'].present?
    persist_config!
  end

  def connect!
    query = config['auth_mode'] == 'pairing_code' ? "?number=#{CGI.escape(config['phone_number_id'])}" : ''
    response = HTTParty.get(
      "#{base_url}/instance/connect/#{CGI.escape(config['instance_name'])}#{query}",
      headers: instance_headers,
      timeout: request_timeout
    )
    raise response_body(response) unless response.success?

    data = response.parsed_response || {}
    config['qrcode_base64'] = data['base64'] || data.dig('qrcode', 'base64')
    config['qrcode_code'] = data['code'] || data.dig('qrcode', 'code')
    config['pairing_code'] = data['pairingCode'] || data.dig('qrcode', 'pairingCode')
    config['connection_status'] = data.dig('instance', 'state') || data.dig('instance', 'status') || data['state'] || 'connecting'
    config['last_error'] = nil
  end

  def disconnect!
    response = HTTParty.delete(
      "#{base_url}/instance/logout/#{CGI.escape(config['instance_name'])}",
      headers: instance_headers,
      timeout: request_timeout
    )
    raise response_body(response) unless response.success?

    config['connection_status'] = 'close'
    config['qrcode_base64'] = nil
    config['qrcode_code'] = nil
    config['pairing_code'] = nil
  end

  def refresh_status!
    response = HTTParty.get(
      "#{base_url}/instance/connectionState/#{CGI.escape(config['instance_name'])}",
      headers: instance_headers,
      timeout: request_timeout
    )
    return unless response.success?

    data = response.parsed_response || {}
    config['connection_status'] = data.dig('instance', 'state') || data.dig('instance', 'status') || data['state'] || config['connection_status']
    if config['connection_status'] == 'open'
      config['qrcode_base64'] = nil
      config['qrcode_code'] = nil
      config['pairing_code'] = nil
    end
  end

  def instance_accessible?
    response = HTTParty.get(
      "#{base_url}/instance/connectionState/#{CGI.escape(config['instance_name'])}",
      headers: instance_headers,
      timeout: [request_timeout, 10].min
    )
    response.success?
  rescue StandardError
    false
  end

  def sync_instance_metadata!
    response = HTTParty.get(
      "#{base_url}/instance/fetchInstances",
      headers: admin_headers,
      timeout: request_timeout
    )
    return unless response.success?

    instances = response.parsed_response
    instances = [instances] unless instances.is_a?(Array)
    instance = instances.find do |item|
      item = item.to_h
      (item['name'] || item['instanceName']).to_s == config['instance_name'].to_s
    end
    return unless instance

    provider = instance['integration'].presence || instance['provider'].presence
    if provider.present?
      config['connect_api_provider'] = provider
      config['calls_supported'] = provider == 'WHATSAPP-ZAPO'
      config['voice_supported'] = provider == 'WHATSAPP-ZAPO'
    end
    config['connect_api_profile_name'] = instance['profileName'] if instance['profileName'].present?
    config['connect_api_profile_picture'] = instance['profilePicUrl'] if instance['profilePicUrl'].present?
  rescue StandardError => e
    Rails.logger.debug("[HUB Connect|API] metadata sync skipped: #{e.class}: #{e.message}")
  end

  def persist_config!
    channel.provider_config = config
  end

  def request_timeout
    value = GlobalConfigService.load('CONNECT_API_REQUEST_TIMEOUT', ENV.fetch('CONNECT_API_REQUEST_TIMEOUT', DEFAULT_TIMEOUT)).to_i
    value.positive? ? value : DEFAULT_TIMEOUT
  end

  def base_url
    @base_url ||= GlobalConfigService.load('CONNECT_API_BASE_URL', ENV.fetch('CONNECT_API_BASE_URL', '')).to_s.sub(%r{/+$}, '').tap do |value|
      raise 'CONNECT_API_BASE_URL is not configured' unless value.start_with?('http://', 'https://')
    end
  end

  def admin_token
    GlobalConfigService.load('CONNECT_API_AUTH_TOKEN', ENV.fetch('CONNECT_API_AUTH_TOKEN', '')).presence || raise('CONNECT_API_AUTH_TOKEN is not configured')
  end

  def admin_headers
    { 'apikey' => admin_token, 'Content-Type' => 'application/json' }
  end

  def instance_headers
    { 'apikey' => config['api_key'], 'Authorization' => "Bearer #{config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def response_body(response)
    parsed = response.parsed_response
    return parsed['message'].to_s if parsed.is_a?(Hash) && parsed['message'].present?
    return parsed['error'].to_s if parsed.is_a?(Hash) && parsed['error'].present?

    response.body.to_s.presence || "HTTP #{response.code}"
  end
end
