# frozen_string_literal: true

require 'net/imap'
require 'net/smtp'
require 'openssl'

module EmailChannel
  class ConnectionProbe
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 20

    def initialize(channel)
      @channel = channel
    end

    def perform(kind)
      case kind.to_s
      when 'imap' then probe_imap
      when 'smtp' then probe_smtp
      else
        raise ArgumentError, 'Tipo de diagnóstico de e-mail inválido.'
      end
    end

    private

    attr_reader :channel

    def probe_imap
      raise ArgumentError, 'IMAP não está habilitado nesta caixa.' unless channel.imap_enabled?
      raise ArgumentError, 'Servidor IMAP não configurado.' if channel.imap_address.blank? || channel.imap_port.to_i <= 0

      client = Net::IMAP.new(
        channel.imap_address,
        port: channel.imap_port,
        ssl: channel.imap_enable_ssl? ? ssl_context : false
      )
      client.login(channel.imap_login, channel.imap_password)
      client.select('INBOX')

      success('imap', channel.imap_address, channel.imap_port, channel.imap_enable_ssl? ? 'ssl/tls' : 'plain')
    ensure
      if defined?(client) && client
        client.logout if client.respond_to?(:logout) && !client.disconnected?
        client.disconnect unless client.disconnected?
      end
    end

    def probe_smtp
      raise ArgumentError, 'SMTP não está habilitado nesta caixa.' unless channel.smtp_enabled?
      raise ArgumentError, 'Servidor SMTP não configurado.' if channel.smtp_address.blank? || channel.smtp_port.to_i <= 0

      smtp = Net::SMTP.new(channel.smtp_address, channel.smtp_port)
      smtp.open_timeout = DEFAULT_OPEN_TIMEOUT
      smtp.read_timeout = DEFAULT_READ_TIMEOUT

      context = ssl_context(channel.smtp_openssl_verify_mode)
      if channel.smtp_enable_ssl_tls?
        smtp.enable_tls(context)
        security = 'ssl/tls'
      elsif channel.smtp_enable_starttls_auto?
        smtp.enable_starttls_auto(context)
        security = 'starttls'
      else
        security = 'plain'
      end

      authentication = normalize_authentication(channel.smtp_authentication)
      if channel.smtp_login.present?
        smtp.start(
          channel.smtp_domain.presence || 'localhost',
          channel.smtp_login,
          channel.smtp_password,
          authentication
        ) {}
      else
        smtp.start(channel.smtp_domain.presence || 'localhost') {}
      end

      success('smtp', channel.smtp_address, channel.smtp_port, security)
    end

    def success(kind, address, port, security)
      {
        ok: true,
        kind: kind,
        address: address,
        port: port,
        security: security,
        checked_at: Time.current.utc.iso8601
      }
    end

    def normalize_authentication(value)
      normalized = value.to_s.tr('-', '_').presence || 'login'
      return normalized.to_sym if %w[plain login cram_md5].include?(normalized)

      :login
    end

    def ssl_context(mode = nil)
      context = OpenSSL::SSL::SSLContext.new
      verify = (mode.presence || (channel.respond_to?(:smtp_openssl_verify_mode) ? channel.smtp_openssl_verify_mode : nil)).to_s
      context.verify_mode = verify == 'none' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      context
    end
  end
end
