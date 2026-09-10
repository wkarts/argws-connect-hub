# frozen_string_literal: true

class Channels::Whatsapp::DeleteConnectApiInstanceJob < ApplicationJob
  queue_as :low

  retry_on ConnectApi::Error, wait: :polynomially_longer, attempts: 8 do |job, error|
    Rails.logger.error("[HUB Connect|API] permanent instance delete failure args=#{job.arguments.inspect}: #{error.message}")
  end

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

    raise
  end
end
