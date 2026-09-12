# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::RecurringCampaignService do
  let(:account) { create(:account) }
  let(:sms_channel) { create(:channel_sms, account: account) }
  let(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let(:first_schedule) { Time.zone.parse('2026-09-12 10:00:00') }
  let(:campaign) do
    create(
      :campaign,
      campaign_type: :ongoing,
      inbox: sms_inbox,
      account: account,
      scheduled_at: first_schedule,
      trigger_rules: { recurrence: { frequency: 'daily', interval: 1 } },
      audience: [{ type: 'Label', id: create(:label, account: account).id }]
    )
  end

  describe '#perform' do
    it 'dispatches through the shared audience service and advances the schedule without completing the campaign' do
      audience_service = instance_double(Campaigns::AudienceCampaignService)
      expect(Campaigns::AudienceCampaignService).to receive(:new).with(campaign: campaign).and_return(audience_service)
      expect(audience_service).to receive(:perform).with(mark_completed: false).and_return(delivered: 1, failed: 0)

      described_class.new(campaign: campaign).perform

      campaign.reload
      expect(campaign).to be_active
      expect(campaign).to be_enabled
      expect(campaign.scheduled_at).to eq(first_schedule + 1.day)
    end

    it 'does not advance the schedule when audience dispatch fails' do
      audience_service = instance_double(Campaigns::AudienceCampaignService)
      allow(Campaigns::AudienceCampaignService).to receive(:new).with(campaign: campaign).and_return(audience_service)
      allow(audience_service).to receive(:perform).with(mark_completed: false)
        .and_raise(Campaigns::AudienceCampaignService::DeliveryError, 'provider unavailable')

      expect do
        described_class.new(campaign: campaign).perform
      end.to raise_error(Campaigns::AudienceCampaignService::DeliveryError)

      expect(campaign.reload.scheduled_at).to eq(first_schedule)
    end

    it 'disables the recurring campaign after its configured end date' do
      campaign.update!(
        trigger_rules: {
          recurrence: {
            frequency: 'daily',
            interval: 1,
            ends_at: (first_schedule + 12.hours).iso8601
          }
        }
      )
      audience_service = instance_double(Campaigns::AudienceCampaignService)
      allow(Campaigns::AudienceCampaignService).to receive(:new).with(campaign: campaign).and_return(audience_service)
      allow(audience_service).to receive(:perform).with(mark_completed: false).and_return(delivered: 1, failed: 0)

      described_class.new(campaign: campaign).perform

      campaign.reload
      expect(campaign).to be_active
      expect(campaign).not_to be_enabled
      expect(campaign.scheduled_at).to eq(first_schedule)
    end

    it 'does not dispatch a disabled recurring campaign' do
      campaign.update!(enabled: false)
      expect(Campaigns::AudienceCampaignService).not_to receive(:new)

      expect(described_class.new(campaign: campaign).perform).to be_nil
    end

    it 'rejects a one-off campaign' do
      campaign.update!(campaign_type: :one_off)

      expect do
        described_class.new(campaign: campaign).perform
      end.to raise_error("Invalid campaign #{campaign.id}")
    end
  end
end
