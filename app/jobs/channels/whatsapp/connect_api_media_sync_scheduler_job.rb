# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiMediaSyncSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    Channel::Whatsapp.where(provider: 'connectapi').find_each do |channel|
      next if ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])
      next if channel.provider_config.to_h['instance_name'].to_s.blank?

      Channels::Whatsapp::ConnectApiMediaSyncJob.perform_later(channel.id)
    end
  end
end
