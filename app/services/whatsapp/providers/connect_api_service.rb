# frozen_string_literal: true

class Whatsapp::Providers::ConnectApiService < Whatsapp::Providers::WhatsappCloudService
  def validate_provider_config?
    Whatsapp::ConnectApiWebhookSetupService.new.perform(whatsapp_channel)
  end

  # Connect|API 1.0.21 Meta-compatible endpoints authenticate with
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
end
