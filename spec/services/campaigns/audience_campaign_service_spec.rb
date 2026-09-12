# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::AudienceCampaignService do
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
    it 'marks one-off campaigns completed before delivering when requested' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:validation_errors).and_return([])
      allow(driver).to receive(:deliverable?).with(contact).and_return(true)
      expect(driver).to receive(:deliver).with(contact) do
        expect(campaign.reload).to be_completed
      end

      described_class.new(campaign: campaign).perform(mark_completed: true)
    end

    it 'does not complete recurring campaigns while delivering' do
      campaign.update!(campaign_type: :ongoing)
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:validation_errors).and_return([])
      allow(driver).to receive(:deliverable?).with(contact).and_return(true)
      expect(driver).to receive(:deliver).with(contact) do
        expect(campaign.reload).to be_active
      end

      described_class.new(campaign: campaign).perform(mark_completed: false)
    end

    it 'skips contacts that cannot be delivered by the selected driver' do
      contact = create(:contact, account: account)
      contact.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:validation_errors).and_return([])
      allow(driver).to receive(:deliverable?).with(contact).and_return(false)
      expect(driver).not_to receive(:deliver)

      described_class.new(campaign: campaign).perform
    end

    it 'only delivers to contacts in the campaign audience labels' do
      included = create(:contact, :with_phone_number, account: account)
      excluded = create(:contact, :with_phone_number, account: account)
      included.update_labels([label.title])
      driver = instance_double(Campaigns::ChannelDrivers::Sms)

      allow(Campaigns::ChannelDriverResolver).to receive(:resolve).with(campaign).and_return(driver)
      allow(driver).to receive(:validation_errors).and_return([])
      allow(driver).to receive(:deliverable?).with(included).and_return(true)
      expect(driver).to receive(:deliver).with(included)
      expect(driver).not_to receive(:deliver).with(excluded)

      described_class.new(campaign: campaign).perform
    end
  end
end
