# frozen_string_literal: true

class Campaigns::ChannelDrivers::Sms < Campaigns::ChannelDrivers::Base
  def deliverable?(contact)
    contact.phone_number.present?
  end

  def deliver(contact)
    channel.send_text_message(contact.phone_number, campaign.message)
  end

  def capabilities
    %w[text variables].freeze
  end
end
