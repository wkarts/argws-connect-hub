# frozen_string_literal: true

class Campaigns::ChannelDriverResolver
  class UnsupportedChannel < StandardError; end

  DRIVERS = {
    'Channel::Sms' => Campaigns::ChannelDrivers::Sms,
    'Channel::TwilioSms' => Campaigns::ChannelDrivers::TwilioSms,
    'Channel::Whatsapp' => Campaigns::ChannelDrivers::Whatsapp
  }.freeze

  class << self
    def supported?(inbox)
      inbox.present? && DRIVERS.key?(inbox.channel_type)
    end

    def resolve(campaign)
      driver_class = DRIVERS[campaign.inbox.channel_type]
      raise UnsupportedChannel, "Unsupported campaign channel: #{campaign.inbox.channel_type}" unless driver_class

      driver_class.new(campaign: campaign)
    end
  end
end
