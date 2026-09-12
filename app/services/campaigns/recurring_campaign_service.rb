# frozen_string_literal: true

class Campaigns::RecurringCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" unless valid_campaign?
    return unless campaign.enabled?

    current_schedule = campaign.scheduled_at || Time.current
    result = Campaigns::AudienceCampaignService.new(campaign: campaign).perform(mark_completed: false)
    next_schedule = campaign.next_scheduled_at(from: current_schedule)

    if next_schedule.present?
      campaign.update!(scheduled_at: next_schedule)
    else
      campaign.update!(enabled: false)
    end

    result
  end

  private

  def valid_campaign?
    campaign.scheduled_recurring_delivery?
  end
end
