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
    it 'marks the campaign completed before delegating the audience to the resolved driver' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:deliverable?).with(contact).and_return(true)
      expect(driver).to receive(:deliver).with(contact) do
        expect(campaign.reload).to be_completed
      end

      described_class.new(campaign: campaign).perform
    end

    it 'skips contacts that the selected driver cannot deliver to' do
      contact = create(:contact, account: account)
      contact.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:deliverable?).with(contact).and_return(false)
      expect(driver).not_to receive(:deliver)

      described_class.new(campaign: campaign).perform
    end

    it 'rejects completed campaigns' do
      campaign.completed!

      expect do
        described_class.new(campaign: campaign).perform
      end.to raise_error('Completed Campaign')
    end
  end
end
