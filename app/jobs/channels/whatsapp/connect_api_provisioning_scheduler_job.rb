# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiProvisioningSchedulerJob < ApplicationJob
  queue_as :low

  VERIFY_INTERVAL = 6.hours

  def perform
    Channel::Whatsapp.where(provider: 'connectapi').find_each do |channel|
      next unless reconciliation_required?(channel)

      reconcile(channel)
    end
  end

  private

  def reconciliation_required?(channel)
    config = channel.provider_config.to_h.deep_stringify_keys
    return true unless config['communication_ready'] == true
    return true unless config['meta_compatible_verified'] == true

    verified_at = Time.zone.parse(config['meta_compatible_verified_at'].to_s)
    verified_at.blank? || verified_at < VERIFY_INTERVAL.ago
  rescue ArgumentError, TypeError
    true
  end

  def reconcile(channel)
    service = Whatsapp::ConnectApiWebhookSetupService.new
    success = service.perform(channel)

    # The setup service is also used during model validation, where the caller
    # persists the channel. Here we persist explicitly without triggering the
    # remote validation again.
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      provider_config: channel.provider_config,
      updated_at: Time.current
    )

    return if success

    Rails.logger.warn("[HUB Connect|API] provisioning reconciliation failed channel=#{channel.id}")
  rescue StandardError => e
    Rails.logger.error(
      "[HUB Connect|API] provisioning reconciliation exception channel=#{channel.id}: #{e.class}: #{e.message}"
    )
  end
end
