# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiDeleteInstanceJob < ApplicationJob
  queue_as :low

  retry_on ConnectApi::Error, wait: 30.seconds, attempts: 5

  def perform(instance_name)
    instance_name = instance_name.to_s.strip
    return if instance_name.blank?

    client.delete_instance(instance_name)
    Rails.logger.info("[HUB Connect|API] deleted remote instance=#{instance_name} after inbox deletion")
  rescue ConnectApi::Error => e
    if e.status.to_i == 404
      Rails.logger.info("[HUB Connect|API] remote instance already absent=#{instance_name}")
      return
    end

    Rails.logger.warn(
      "[HUB Connect|API] remote instance deletion failed instance=#{instance_name} " \
      "status=#{e.status || 'n/a'} error=#{e.message}"
    )
    raise
  end

  private

  def client
    @client ||= ConnectApi::Client.new
  end
end
