# frozen_string_literal: true

class Campaigns::ChannelDrivers::TwilioSms < Campaigns::ChannelDrivers::Base
  def deliverable?(contact)
    contact.phone_number.present?
  end

  def deliver(contact)
    channel.send_message(to: contact.phone_number, body: campaign.message)
  end

  def capabilities
    %w[text variables].freeze
  end
end
