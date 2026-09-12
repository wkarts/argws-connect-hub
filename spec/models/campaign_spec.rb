# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaign do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:inbox) }
  end

  describe '.before_create' do
    let(:account) { create(:account) }
    let(:website_channel) { create(:channel_widget, account: account) }
    let(:website_inbox) { create(:inbox, channel: website_channel, account: account) }
    let(:campaign) { build(:campaign, inbox: website_inbox, display_id: nil, trigger_rules: { url: 'https://test.com' }) }

    before do
      campaign.save!
      campaign.reload
    end

    it 'runs before_create callbacks' do
      expect(campaign.display_id).to eq(1)
    end
  end

  context 'when Inbox other then Website or supported one-off channels' do
    before do
      stub_request(:post, /graph.facebook.com/)
    end

    let!(:facebook_channel) { create(:channel_facebook_page) }
    let!(:facebook_inbox) { create(:inbox, channel: facebook_channel) }
    let(:campaign) { build(:campaign, inbox: facebook_inbox) }

    it 'would not save the campaigns' do
      expect(campaign.save).to be false
      expect(campaign.errors.full_messages.first).to eq 'Inbox Unsupported Inbox type'
    end
  end

  context 'when a campaign is completed' do
    let(:account) { create(:account) }
    let(:web_widget) { create(:channel_widget, account: account) }
    let!(:campaign) { create(:campaign, inbox: web_widget.inbox, campaign_status: :completed, trigger_rules: { url: 'https://test.com' }) }

    it 'would prevent further updates' do
      campaign.title = 'new name'
      expect(campaign.save).to be false
      expect(campaign.errors.full_messages.first).to eq 'Status The campaign is already completed'
    end

    it 'can be deleted' do
      campaign.destroy!
      expect(described_class.exists?(campaign.id)).to be false
    end

    it 'cant be triggered' do
      expect(Campaigns::OneoffCampaignService).not_to receive(:new).with(campaign: campaign)
      expect(campaign.trigger!).to be_nil
    end
  end

  describe 'ensure_correct_campaign_attributes' do
    context 'when Twilio SMS campaign' do
      let!(:twilio_sms) { create(:channel_twilio_sms) }
      let!(:twilio_inbox) { create(:inbox, channel: twilio_sms) }
      let(:campaign) { build(:campaign, inbox: twilio_inbox) }

      it 'only saves campaign type as oneoff and wont leave scheduled_at empty' do
        campaign.campaign_type = 'ongoing'
        campaign.save!
        expect(campaign.reload.campaign_type).to eq 'one_off'
        expect(campaign.scheduled_at.present?).to be true
      end

      it 'calls the polymorphic one-off service on trigger!' do
        campaign_service = double
        expect(Campaigns::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(campaign_service)
        expect(campaign_service).to receive(:perform)
        campaign.save!
        campaign.trigger!
      end
    end

    context 'when SMS campaign' do
      let!(:sms_channel) { create(:channel_sms) }
      let!(:sms_inbox) { create(:inbox, channel: sms_channel) }
      let(:campaign) { build(:campaign, inbox: sms_inbox) }

      it 'only saves campaign type as oneoff and wont leave scheduled_at empty' do
        campaign.campaign_type = 'ongoing'
        campaign.save!
        expect(campaign.reload.campaign_type).to eq 'one_off'
        expect(campaign.scheduled_at.present?).to be true
      end

      it 'calls the polymorphic one-off service on trigger!' do
        campaign_service = double
        expect(Campaigns::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(campaign_service)
        expect(campaign_service).to receive(:perform)
        campaign.save!
        campaign.trigger!
      end
    end

    context 'when WhatsApp campaign' do
      let(:account) { create(:account) }
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          account: account,
          validate_provider_config: false,
          sync_templates: false,
          provider_config: {
            'api_key' => 'test_key',
            'instance_name' => 'campaign-instance'
          }
        )
      end
      let(:whatsapp_inbox) { whatsapp_channel.inbox }
      let(:template_params) do
        {
          'name' => 'sample_shipping_confirmation',
          'language' => 'en_US',
          'processed_params' => { '1' => '3' }
        }
      end
      let(:campaign) do
        build(
          :campaign,
          inbox: whatsapp_inbox,
          account: account,
          message_attributes: { 'template_params' => template_params }
        )
      end

      it 'saves as one-off and exposes template capabilities' do
        campaign.save!

        expect(campaign.reload.campaign_type).to eq 'one_off'
        expect(campaign.scheduled_at).to be_present
        expect(campaign.channel_capabilities).to include('template', 'variables')
      end

      it 'requires template params for a WhatsApp campaign' do
        campaign.message_attributes = {}

        expect(campaign).not_to be_valid
        expect(campaign.errors[:message_attributes]).to include('template_params is required for WhatsApp campaigns')
      end

      it 'calls the polymorphic one-off service on trigger!' do
        campaign_service = double
        expect(Campaigns::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(campaign_service)
        expect(campaign_service).to receive(:perform)

        campaign.save!
        campaign.trigger!
      end
    end

    context 'when Website campaign' do
      let(:campaign) { build(:campaign) }

      it 'only saves campaign type as ongoing' do
        campaign.campaign_type = 'one_off'
        campaign.save!
        expect(campaign.reload.campaign_type).to eq 'ongoing'
      end
    end
  end
end
