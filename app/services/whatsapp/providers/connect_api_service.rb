# frozen_string_literal: true

class Whatsapp::Providers::ConnectApiService < Whatsapp::Providers::WhatsappCloudService
  def validate_provider_config?
    Whatsapp::ConnectApiWebhookSetupService.new.perform(whatsapp_channel)
  end

  # HUB is a trusted server-to-server client of Connect|API. Prefer the
  # installation-level credential for Graph-compatible requests so a stale or
  # rotated per-instance token cannot break message delivery after an instance
  # reconnect/migration. The instance token remains a compatibility fallback.
  def api_headers
    token = hub_graph_token
    raise 'CONNECT_API_AUTH_TOKEN is not configured' if token.blank?

    {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json'
    }
  end

  # Connect|API Meta-compatible endpoints authenticate with
  # Authorization: Bearer. Do not rely on Meta's legacy access_token query form.
  def sync_templates
    whatsapp_channel.mark_message_templates_updated

    response = HTTParty.get(
      "#{business_account_path}/message_templates",
      headers: api_headers
    )

    templates = response.success? ? Array(response['data']) : []
    whatsapp_channel.update(
      message_templates: templates,
      message_templates_last_updated: Time.now.utc
    )
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] template sync skipped: #{e.class}: #{e.message}")
    []
  end

  private

  def hub_graph_token
    GlobalConfigService.load(
      'CONNECT_API_AUTH_TOKEN',
      ENV.fetch('CONNECT_API_AUTH_TOKEN', '')
    ).to_s.strip.presence || whatsapp_channel.provider_config['api_key'].to_s.strip.presence
  end
end
