# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::TriggerCampaignJob do
  let(:account) { create(:account) }
  let(:sms_channel) { create(:channel_sms, account: account) }
  let(:inbox) { create(:inbox, channel: sms_channel, account: account) }

  it 'triggers a due campaign when the queued schedule still matches' do
    campaign = create(:campaign, account: account, inbox: inbox, scheduled_at: 1.minute.ago)
    expected_schedule = campaign.scheduled_at.iso8601(6)

    expect_any_instance_of(Campaign).to receive(:trigger!).once

    described_class.perform_now(campaign.id, expected_schedule)
  end

  it 'ignores a stale delayed job after the campaign was rescheduled' do
    campaign = create(:campaign, account: account, inbox: inbox, scheduled_at: 1.minute.ago)
    stale_schedule = campaign.scheduled_at.iso8601(6)
    campaign.update!(scheduled_at: 1.hour.from_now)

    expect_any_instance_of(Campaign).not_to receive(:trigger!)

    described_class.perform_now(campaign.id, stale_schedule)
  end

  it 'does not trigger a campaign before its scheduled time' do
    campaign = create(:campaign, account: account, inbox: inbox, scheduled_at: 1.hour.from_now)

    expect_any_instance_of(Campaign).not_to receive(:trigger!)

    described_class.perform_now(campaign.id, campaign.scheduled_at.iso8601(6))
  end
end
