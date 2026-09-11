# frozen_string_literal: true

class Webhooks::ConnectApiCallEventsJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5

  def perform(params = {}, channel_id = nil)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return if channel.blank?
    return if channel.reauthorization_required?
    return unless channel.account.active?

    Whatsapp::IncomingConnectApiCallService.new(channel: channel, params: params).perform
  end
end
