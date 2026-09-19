# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiRealtimeWebhookHealthJob < ApplicationJob
  queue_as :high
  self.log_arguments = false

  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return unless channel&.inbox

    Whatsapp::ConnectApiRealtimeWebhookService.new(channel: channel).ensure!
  end
end
