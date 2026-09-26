# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiMediaSyncSchedulerJob < ApplicationJob
  queue_as :low
  self.log_arguments = false

  DEFAULT_MIN_INTERVAL_SECONDS = 180
  MIN_INTERVAL_SECONDS = 60
  MAX_INTERVAL_SECONDS = 3600

  def perform
    return unless recovery_enabled?

    Channel::Whatsapp.where(provider: 'connectapi').find_each do |channel|
      next if ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])
      next if channel.provider_config.to_h['instance_name'].to_s.blank?
      next unless recovery_slot_acquired?(channel.id)

      Channels::Whatsapp::ConnectApiMediaSyncJob.perform_later(channel.id)
    end
  end

  private

  def recovery_enabled?
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch('HUB_CONNECT_RECOVERY_ENABLED', 'true')
    )
  end

  def recovery_slot_acquired?(channel_id)
    Rails.cache.write(
      "hub:connect_api:recovery:#{channel_id}",
      Time.current.to_i,
      expires_in: recovery_interval.seconds,
      unless_exist: true
    )
  rescue StandardError => error
    Rails.logger.warn(
      "[HUB Connect|API] recovery throttle unavailable channel=#{channel_id}: "       "#{error.class}: #{error.message}"
    )
    true
  end

  def recovery_interval
    value = ENV.fetch(
      'HUB_CONNECT_RECOVERY_MIN_INTERVAL_SECONDS',
      DEFAULT_MIN_INTERVAL_SECONDS
    ).to_i

    value.clamp(MIN_INTERVAL_SECONDS, MAX_INTERVAL_SECONDS)
  end
end
