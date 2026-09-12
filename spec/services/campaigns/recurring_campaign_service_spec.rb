# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::RecurringCampaignService do
  let(:account) { create(:account) }
  let(:sms_channel) { create(:channel_sms, account: account) }
  let(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let(:campaign) do
    create(
      :campaign,
      campaign_type: :ongoing,
      inbox: sms_inbox,
      account: account,
      audience: [{ type: 'Label', id: create(:label, account: account).id }]
    )
  end

  describe '#perform' do
    it 'dispatches through the shared audience service without completing the campaign' do
      audience_service = instance_double(Campaigns::AudienceCampaignService)
      expect(Campaigns::AudienceCampaignService).to receive(:new).with(campaign: campaign).and_return(audience_service)
      expect(audience_service).to receive(:perform).with(mark_completed: false)

      described_class.new(campaign: campaign).perform
      expect(campaign.reload).to be_active
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
