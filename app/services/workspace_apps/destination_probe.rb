require 'net/http'
require 'openssl'
require 'resolv'
require 'ipaddr'
require 'timeout'
require 'time'
require 'uri'

module WorkspaceApps
  class DestinationProbe
    class Rejected < StandardError; end
    BLOCKED_V4 = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
                    192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15
                    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4].map { |range| IPAddr.new(range) }.freeze
    BLOCKED_V6 = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map { |range| IPAddr.new(range) }.freeze
    GLOBAL_V6 = IPAddr.new('2000::/3')

    def initialize(url:, hub_origin:)
      @url = url
      @hub_origin = hub_origin
      @steps = []
    end

    def call
      result = Timeout.timeout(8) { probe }
      result.merge(hub_origin: @hub_origin, checked_at: Time.now.utc.iso8601, scope: 'anonymous_server_head', steps: @steps)
    rescue Rejected => e
      failure(e.message)
    rescue Resolv::ResolvError, SocketError
      failure('dns_error')
    rescue OpenSSL::SSL::SSLError
      failure('tls_error')
    rescue Timeout::Error
      failure('timeout')
    rescue Errno::ECONNREFUSED
      failure('connection_refused')
    rescue IOError, SystemCallError, Net::HTTPBadResponse, Net::ProtocolError, URI::InvalidURIError, ArgumentError
      failure('network_error')
    end

    def self.public_address?(value)
      address = IPAddr.new(value)
      if address.ipv4?
        BLOCKED_V4.none? { |range| range.include?(address) }
      else
        GLOBAL_V6.include?(address) && BLOCKED_V6.none? { |range| range.include?(address) }
      end
    rescue IPAddr::InvalidAddressError
      false
    end

    private

    def probe
      current = @url
      4.times do |index|
        uri = destination(current)
        addresses = Resolv.getaddresses(uri.hostname)
        raise Rejected, 'dns_error' if addresses.empty?
        raise Rejected, 'blocked_address' unless addresses.all? { |address| self.class.public_address?(address) }

        response = request_head(uri, addresses.first)
        @steps << { url: display_url(uri), status: response.code.to_i }
        if [301, 302, 303, 307, 308].include?(response.code.to_i)
          raise Rejected, 'redirect_limit' if index == 3 || response['location'].to_s.empty?

          current = URI.join(uri.to_s, response['location']).to_s
          next
        end
        headers = %w[x-frame-options content-security-policy content-security-policy-report-only].to_h do |name|
          [name, (response.get_fields(name) || []).map { |value| value[0, 8192] }]
        end
        policy = FramePolicy.new(headers: headers, destination: uri.to_s, parent: @hub_origin).call
        return policy.merge(code: response.code.to_i.between?(200, 299) ? 'headers_checked' : 'http_status',
                            status: response.code.to_i, destination: display_url(uri))
      end
    end

    def destination(value)
      raise Rejected, 'invalid_url' unless value.is_a?(String) && value.length <= 2048 && !value.match?(/[\s\\\x00-\x1f]/)

      uri = URI(value)
      raise Rejected, 'invalid_url' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo

      uri.fragment = nil
      uri
    end

    def request_head(uri, address)
      # Pin the validated IP to prevent DNS rebinding. Hostname is retained for
      # SNI/certificate checks. Explicit nil disables environment HTTP proxies.
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.ipaddr = address
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 2
      http.read_timeout = 3
      http.write_timeout = 2
      http.max_retries = 0
      request = Net::HTTP::Head.new(uri.request_uri)
      request['User-Agent'] = 'HUB-Workspace-Diagnostics/1.0'
      request['Accept'] = 'text/html'
      http.start { |connection| connection.request(request) }
    end

    def display_url(uri)
      clean = uri.dup
      clean.query = nil
      clean.fragment = nil
      clean.to_s
    end

    def failure(code)
      { code: code, verdict: 'inconclusive', hub_origin: @hub_origin, steps: @steps,
        checked_at: Time.now.utc.iso8601, scope: 'anonymous_server_head' }
    end
  end
end
