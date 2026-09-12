# frozen_string_literal: true

class Campaigns::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" unless valid_campaign?
    raise 'Completed Campaign' if campaign.completed?

    Campaigns::AudienceCampaignService.new(campaign: campaign).perform(mark_completed: true)
  end

  private

  def valid_campaign?
    campaign.one_off? && Campaigns::ChannelDriverResolver.supported?(campaign.inbox)
  end
end
