# frozen_string_literal: true

class Campaigns::ChannelDrivers::Base
  pattr_initialize [:campaign!]

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def deliverable?(_contact)
    true
  end

  def deliver(_contact)
    raise NotImplementedError, "#{self.class.name} must implement #deliver"
  end

  def capabilities
    []
  end
end
