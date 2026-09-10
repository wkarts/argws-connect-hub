# frozen_string_literal: true

class Channels::Whatsapp::DeleteConnectApiInstanceJob < ApplicationJob
  queue_as :low

  def perform(instance_name)
    name = instance_name.to_s.strip
    return if name.blank?

    ConnectApi::Client.new.delete_instance(name)
    Rails.logger.info("[HUB Connect|API] deleted remote instance name=#{name}")
  rescue ConnectApi::Error => e
    if e.status.to_i == 404
      Rails.logger.info("[HUB Connect|API] remote instance already absent name=#{name}")
      return
    end

    # Re-raise transient/server failures. Sidekiq keeps its normal retry policy,
    # without resolving ConnectApi::Error at class-load time during eager_load.
    raise
  end
end
