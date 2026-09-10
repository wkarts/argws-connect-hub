# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiProvisioningSchedulerJob < ApplicationJob
  queue_as :low

  VERIFY_INTERVAL = 6.hours

  def perform
    Channel::Whatsapp.where(provider: 'connectapi').find_each do |channel|
      next if manual_instance_deletion?(channel)
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

    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      provider_config: channel.provider_config,
      updated_at: Time.current
    )

    if success
      Channels::Whatsapp::ConnectApiMediaSyncJob.perform_later(channel.id)
      Channels::Whatsapp::ConnectApiProfilePictureSchedulerJob.perform_later
      return
    end

    Rails.logger.warn("[HUB Connect|API] provisioning reconciliation failed channel=#{channel.id}")
  rescue StandardError => e
    Rails.logger.error(
      "[HUB Connect|API] provisioning reconciliation exception channel=#{channel.id}: #{e.class}: #{e.message}"
    )
  end

  def manual_instance_deletion?(channel)
    ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])
  end
end
