# frozen_string_literal: true

require 'cgi'

module ConnectApi
  class Error < StandardError
    attr_reader :status, :payload

    def initialize(message, status: nil, payload: nil)
      super(message)
      @status = status
      @payload = payload
    end
  end

  class Client
    DEFAULT_TIMEOUT = 60

    attr_reader :base_url

    def initialize(base_url: nil, api_key: nil, timeout: nil)
      @base_url = normalize_base_url(base_url || configured_base_url)
      @api_key = api_key.presence || configured_api_key
      @timeout = positive_integer(timeout || configured_timeout, DEFAULT_TIMEOUT)
    end

    def configured?
      base_url.present? && @api_key.present?
    end

    def root
      request(:get, '/', authenticated: false)
    end

    def health
      request(:get, '/health', authenticated: false)
    end

    def fetch_instances
      response = request(:get, '/instance/fetchInstances')
      response.is_a?(Array) ? response : Array.wrap(response)
    end

    def connection_state(instance_name)
      request(:get, "/instance/connectionState/#{escape(instance_name)}")
    end

    def connect(instance_name, number: nil)
      query = number.present? ? "?number=#{CGI.escape(number.to_s.gsub(/\D/, ''))}" : ''
      request(:get, "/instance/connect/#{escape(instance_name)}#{query}")
    end

    def restart(instance_name)
      request(:post, "/instance/restart/#{escape(instance_name)}")
    end

    def logout(instance_name)
      request(:delete, "/instance/logout/#{escape(instance_name)}")
    end

    def delete_instance(instance_name)
      request(:delete, "/instance/delete/#{escape(instance_name)}")
    end

    def migrate_provider(instance_name, target_provider:, dry_run: false)
      request(
        :post,
        "/instance/migrateProvider/#{escape(instance_name)}",
        body: { targetProvider: target_provider, dryRun: dry_run }
      )
    end

    def find_settings(instance_name)
      request(:get, "/settings/find/#{escape(instance_name)}")
    end

    def set_settings(instance_name, settings)
      request(:post, "/settings/set/#{escape(instance_name)}", body: settings)
    end

    def list_calls(instance_name)
      response = request(:get, "/call/list/#{escape(instance_name)}")
      response.is_a?(Array) ? response : Array.wrap(response)
    end

    def offer_call(instance_name, number:, is_video: false, call_duration: nil)
      body = {
        number: number.to_s.gsub(/\D/, ''),
        isVideo: ActiveModel::Type::Boolean.new.cast(is_video)
      }
      body[:callDuration] = call_duration.to_i if call_duration.present? && call_duration.to_i.positive?
      request(:post, "/call/offer/#{escape(instance_name)}", body: body)
    end

    def accept_call(instance_name, call_id)
      call_action(instance_name, 'accept', call_id: call_id)
    end

    def reject_call(instance_name, call_id)
      call_action(instance_name, 'reject', call_id: call_id)
    end

    def end_call(instance_name, call_id)
      call_action(instance_name, 'end', call_id: call_id)
    end

    def mute_call(instance_name, call_id, muted:)
      request(
        :post,
        "/call/mute/#{escape(instance_name)}",
        body: { callId: call_id.to_s, muted: ActiveModel::Type::Boolean.new.cast(muted) }
      )
    end

    def media_ticket(instance_name, call_id)
      request(
        :post,
        "/call/mediaTicket/#{escape(instance_name)}",
        body: { callId: call_id.to_s }
      )
    end

    def request(method, path, body: nil, authenticated: true, timeout: nil)
      raise Error, 'CONNECT_API_BASE_URL is not configured' if base_url.blank?
      raise Error, 'CONNECT_API_AUTH_TOKEN is not configured' if authenticated && @api_key.blank?

      headers = { 'Content-Type' => 'application/json' }
      headers['apikey'] = @api_key if authenticated

      options = {
        headers: headers,
        timeout: positive_integer(timeout || @timeout, @timeout)
      }
      options[:body] = body.to_json unless body.nil?

      response = HTTParty.public_send(method, "#{base_url}#{normalized_path(path)}", options)
      payload = parse_response(response)
      return payload if response.success?

      raise Error.new(error_message(payload, response), status: response.code, payload: payload)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Error.new("Connect|API timeout: #{e.message}", status: 504)
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise Error.new("Connect|API indisponível: #{e.message}", status: 503)
    end

    private

    def configured_base_url
      GlobalConfigService.load('CONNECT_API_BASE_URL', ENV.fetch('CONNECT_API_BASE_URL', '')).to_s
    end

    def configured_api_key
      GlobalConfigService.load('CONNECT_API_AUTH_TOKEN', ENV.fetch('CONNECT_API_AUTH_TOKEN', '')).to_s
    end

    def configured_timeout
      GlobalConfigService.load('CONNECT_API_REQUEST_TIMEOUT', ENV.fetch('CONNECT_API_REQUEST_TIMEOUT', DEFAULT_TIMEOUT)).to_s
    end

    def normalize_base_url(value)
      normalized = value.to_s.strip.sub(%r{/+$}, '')
      return normalized if normalized.blank? || normalized.start_with?('http://', 'https://')

      raise Error, 'CONNECT_API_BASE_URL must be an absolute HTTP(S) URL'
    end

    def normalized_path(path)
      value = path.to_s
      value.start_with?('/') ? value : "/#{value}"
    end

    def escape(value)
      CGI.escape(value.to_s)
    end

    def call_action(instance_name, action, call_id:)
      request(:post, "/call/#{action}/#{escape(instance_name)}", body: { callId: call_id.to_s })
    end

    def parse_response(response)
      parsed = response.parsed_response
      parsed.nil? ? response.body.to_s : parsed
    rescue JSON::ParserError
      response.body.to_s
    end

    def error_message(payload, response)
      if payload.is_a?(Hash)
        value = payload['message'] || payload['error'] || payload.dig('response', 'message')
        return Array(value).join(', ') if value.present?
      end

      response.body.to_s.presence || "Connect|API HTTP #{response.code}"
    end

    def positive_integer(value, fallback)
      parsed = value.to_i
      parsed.positive? ? parsed : fallback
    end
  end
end
