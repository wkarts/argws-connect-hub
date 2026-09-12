# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::OneoffCampaignService do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account) }
  let(:sms_channel) { create(:channel_sms, account: account) }
  let(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let(:campaign) do
    create(
      :campaign,
      inbox: sms_inbox,
      account: account,
      audience: [{ type: 'Label', id: label.id }]
    )
  end

  describe '#perform' do
    it 'delegates audience delivery and completion to the shared service' do
      audience_service = instance_double(Campaigns::AudienceCampaignService)
      expect(Campaigns::AudienceCampaignService).to receive(:new).with(campaign: campaign).and_return(audience_service)
      expect(audience_service).to receive(:perform).with(mark_completed: true)

      described_class.new(campaign: campaign).perform
    end

    it 'rejects completed campaigns' do
      campaign.completed!

      expect do
        described_class.new(campaign: campaign).perform
      end.to raise_error('Completed Campaign')
    end

    it 'rejects recurring campaigns' do
      campaign.update!(campaign_type: :ongoing)

      expect do
        described_class.new(campaign: campaign).perform
      end.to raise_error("Invalid campaign #{campaign.id}")
    end
  end
end
