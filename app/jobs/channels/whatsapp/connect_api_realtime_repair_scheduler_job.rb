# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiRealtimeRepairSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    Channel::Whatsapp.where(provider: 'connectapi').includes(:inbox).find_each do |channel|
      next unless channel.inbox
      next if ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])
      next if channel.provider_config.to_h['instance_name'].to_s.blank?

      Whatsapp::ConnectApiRealtimeWebhookService.new(channel: channel).ensure!
    rescue StandardError => e
      Rails.logger.warn(
        "[HUB Connect|API] automatic realtime repair failed channel=#{channel.id}: #{e.class}: #{e.message}"
      )
    end
  end
end
