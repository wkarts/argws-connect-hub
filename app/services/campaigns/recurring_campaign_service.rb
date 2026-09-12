# frozen_string_literal: true

class Campaigns::RecurringCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" unless valid_campaign?
    return unless campaign.enabled?

    Campaigns::AudienceCampaignService.new(campaign: campaign).perform(mark_completed: false)
  end

  private

  def valid_campaign?
    campaign.ongoing? && Campaigns::ChannelDriverResolver.supported?(campaign.inbox)
  end
end
