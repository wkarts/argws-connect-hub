# frozen_string_literal: true

require 'digest'
require 'ipaddr'
require 'net/http'
require 'nokogiri'
require 'resolv'
require 'uri'

module LinkPreviews
  class Fetcher
    class Error < StandardError; end

    MAX_URL_LENGTH = 2048
    MAX_REDIRECTS = 3
    MAX_BODY_BYTES = 512.kilobytes
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 4
    CACHE_TTL = 30.minutes

    BLOCKED_NETWORKS = %w[
      0.0.0.0/8
      10.0.0.0/8
      100.64.0.0/10
      127.0.0.0/8
      169.254.0.0/16
      172.16.0.0/12
      192.0.0.0/24
      192.0.2.0/24
      192.168.0.0/16
      198.18.0.0/15
      198.51.100.0/24
      203.0.113.0/24
      224.0.0.0/4
      240.0.0.0/4
      ::/128
      ::1/128
      fc00::/7
      fe80::/10
      ff00::/8
      2001:db8::/32
    ].map { |network| IPAddr.new(network) }.freeze

    def initialize(url)
      @url = url.to_s.strip
    end

    def perform
      raise Error, 'URL inválida.' if @url.blank? || @url.length > MAX_URL_LENGTH

      cache_key = "hub:link_preview:v1:#{Digest::SHA256.hexdigest(@url)}"
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_preview(@url)
      end
    end

    private

    def fetch_preview(value, redirects = 0)
      raise Error, 'Muitos redirecionamentos.' if redirects > MAX_REDIRECTS

      uri, ip = safe_uri_and_ip!(value)
      response, body = request(uri, ip)

      if response.is_a?(Net::HTTPRedirection)
        location = response['location'].to_s
        raise Error, 'Redirecionamento inválido.' if location.blank?

        next_url = URI.join(uri.to_s, location).to_s
        return fetch_preview(next_url, redirects + 1)
      end

      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      content_type = response['content-type'].to_s.downcase
      raise Error, 'Conteúdo não é HTML.' unless content_type.include?('text/html') || content_type.include?('application/xhtml')

      build_preview(uri, body)
    end

    def request(uri, ip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = ip if http.respond_to?(:ipaddr=)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.write_timeout = OPEN_TIMEOUT if http.respond_to?(:write_timeout=)

      request = Net::HTTP::Get.new(uri.request_uri)
      request['User-Agent'] = 'HUB-LinkPreview/1.0'
      request['Accept'] = 'text/html,application/xhtml+xml;q=0.9'
      request['Accept-Encoding'] = 'identity'

      body = +''
      response = http.request(request) do |res|
        res.read_body do |chunk|
          body << chunk
          raise Error, 'Página excede o limite de pré-visualização.' if body.bytesize > MAX_BODY_BYTES
        end
      end

      [response, body]
    rescue Timeout::Error, IOError, SocketError, SystemCallError, Net::HTTPBadResponse => error
      raise Error, "Falha ao carregar URL: #{error.class}"
    end

    def safe_uri_and_ip!(value)
      uri = URI.parse(value)
      raise Error, 'Apenas URLs HTTP/HTTPS são permitidas.' unless %w[http https].include?(uri.scheme)
      raise Error, 'Host inválido.' if uri.host.blank? || uri.userinfo.present?
      raise Error, 'Porta não permitida.' unless [80, 443].include?(uri.port)

      hostname = uri.host.downcase
      raise Error, 'Host não permitido.' if hostname == 'localhost' || hostname.end_with?('.localhost')

      addresses = Resolv.getaddresses(hostname)
      raise Error, 'Host não resolvido.' if addresses.empty?

      public_addresses = addresses.filter_map do |address|
        ip = IPAddr.new(address)
        next if blocked_ip?(ip)

        address
      rescue IPAddr::InvalidAddressError
        nil
      end

      raise Error, 'Endereço de rede não permitido.' if public_addresses.empty?
      raise Error, 'Host resolve para rede não permitida.' if public_addresses.length != addresses.length

      [uri, public_addresses.first]
    rescue URI::InvalidURIError
      raise Error, 'URL inválida.'
    end

    def blocked_ip?(ip)
      BLOCKED_NETWORKS.any? { |network| network.include?(ip) }
    end

    def build_preview(uri, html)
      document = Nokogiri::HTML(html)

      title = metadata(document, 'og:title') || document.at_css('title')&.text
      description = metadata(document, 'og:description') || named_metadata(document, 'description')
      site_name = metadata(document, 'og:site_name')
      image = metadata(document, 'og:image') || metadata(document, 'twitter:image')
      canonical = document.at_css('link[rel="canonical"]')&.[]('href').to_s.presence

      resolved_url = canonical ? resolve_url(uri, canonical) : uri.to_s
      resolved_image = image ? resolve_public_asset_url(uri, image) : nil

      {
        url: sanitize_url(resolved_url || uri.to_s),
        title: clean_text(title, 180),
        description: clean_text(description, 320),
        site_name: clean_text(site_name, 80),
        image_url: resolved_image,
        host: uri.host
      }.compact
    end

    def metadata(document, property)
      document.at_css(%(meta[property="#{property}"]))&.[]('content').to_s.presence
    end

    def named_metadata(document, name)
      document.at_css(%(meta[name="#{name}"]))&.[]('content').to_s.presence
    end

    def clean_text(value, limit)
      value.to_s.gsub(/\s+/, ' ').strip.truncate(limit).presence
    end

    def resolve_url(base_uri, value)
      URI.join(base_uri.to_s, value.to_s).to_s
    rescue URI::InvalidURIError
      nil
    end

    def resolve_public_asset_url(base_uri, value)
      url = resolve_url(base_uri, value)
      return if url.blank?

      uri, = safe_uri_and_ip!(url)
      sanitize_url(uri.to_s)
    rescue Error
      nil
    end

    def sanitize_url(value)
      uri = URI.parse(value.to_s)
      uri.user = nil if uri.respond_to?(:user=)
      uri.password = nil if uri.respond_to?(:password=)
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      value.to_s
    end
  end
end
