class Sms::OneoffSmsCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" unless campaign.inbox.channel_type == 'Channel::Sms' && campaign.one_off?

    Campaigns::OneoffCampaignService.new(campaign: campaign).perform
  end
end
