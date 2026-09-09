# HUB installation-local defaults.
# Runtime URLs are derived from FRONTEND_URL instead of hard-coded product domains.
require 'uri'

module HubDefaults
  module_function

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000').to_s.sub(%r{/$}, '')
  end

  def frontend_host
    URI.parse(frontend_url).host || 'localhost'
  rescue URI::InvalidURIError
    'localhost'
  end

  def mailer_sender
    configured = ENV.fetch('MAILER_SENDER_EMAIL', '').to_s.strip
    return configured unless configured.empty?

    "HUB <no-reply@#{frontend_host}>"
  end

  def support_email
    configured = ENV.fetch('HUB_SUPPORT_EMAIL', '').to_s.strip
    return configured unless configured.empty?

    "support@#{frontend_host}"
  end
end
