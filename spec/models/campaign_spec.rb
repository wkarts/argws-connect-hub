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

    it 'keeps a schedule for website campaigns too' do
      expect(campaign.scheduled_at).to be_present
    end
  end

  context 'when Inbox other then Website or supported campaign channels' do
    before do
      stub_request(:post, /graph.facebook.com/)
    end

    let!(:facebook_channel) { create(:channel_facebook_page) }
    let!(:facebook_inbox) { create(:inbox, channel: facebook_channel) }
    let(:campaign) { build(:campaign, inbox: facebook_inbox) }

    it 'does not save campaigns' do
      expect(campaign.save).to be false
      expect(campaign.errors.full_messages.first).to eq 'Inbox Unsupported Inbox type'
    end
  end

  context 'when a campaign is completed' do
    let(:account) { create(:account) }
    let(:web_widget) { create(:channel_widget, account: account) }
    let!(:campaign) { create(:campaign, inbox: web_widget.inbox, campaign_status: :completed, trigger_rules: { url: 'https://test.com' }) }

    it 'prevents further updates' do
      campaign.title = 'new name'
      expect(campaign.save).to be false
      expect(campaign.errors.full_messages.first).to eq 'Status The campaign is already completed'
    end

    it 'can be deleted' do
      campaign.destroy!
      expect(described_class.exists?(campaign.id)).to be false
    end

    it 'cannot be triggered' do
      expect(Campaigns::OneoffCampaignService).not_to receive(:new).with(campaign: campaign)
      expect(Campaigns::RecurringCampaignService).not_to receive(:new).with(campaign: campaign)
      expect(campaign.trigger!).to be_nil
    end
  end

  describe 'campaign channel modes' do
    shared_examples 'polymorphic outbound campaign channel' do
      it 'keeps the legacy implicit campaign as one-off' do
        campaign.save!

        expect(campaign.reload).to be_one_off
        expect(campaign.scheduled_at).to be_present
      end

      it 'allows an explicit recurring campaign with a real schedule' do
        campaign.campaign_type = 'ongoing'
        campaign.save!

        expect(campaign.reload).to be_ongoing
        expect(campaign.scheduled_at).to be_present
        expect(campaign.recurrence_config).to include('frequency' => 'daily', 'interval' => 1)
        expect(campaign.channel_capabilities).to include('one_off', 'ongoing', 'schedule', 'materials')
      end

      it 'dispatches explicit recurring campaigns through the recurring service' do
        campaign.campaign_type = 'ongoing'
        campaign.save!
        campaign_service = double

        expect(Campaigns::RecurringCampaignService).to receive(:new).with(campaign: campaign).and_return(campaign_service)
        expect(campaign_service).to receive(:perform)

        campaign.trigger!
      end

      it 'calculates the next recurring execution from the stored schedule' do
        first_run = Time.zone.parse('2026-09-12 10:00:00')
        campaign.campaign_type = 'ongoing'
        campaign.scheduled_at = first_run
        campaign.trigger_rules = { 'recurrence' => { 'frequency' => 'hourly', 'interval' => 2 } }
        campaign.save!

        expect(campaign.next_scheduled_at(from: first_run)).to eq(first_run + 2.hours)
      end
    end

    context 'when Twilio SMS campaign' do
      let!(:twilio_sms) { create(:channel_twilio_sms) }
      let!(:twilio_inbox) { create(:inbox, channel: twilio_sms) }
      let(:campaign) { build(:campaign, inbox: twilio_inbox) }

      include_examples 'polymorphic outbound campaign channel'
    end

    context 'when SMS campaign' do
      let!(:sms_channel) { create(:channel_sms) }
      let!(:sms_inbox) { create(:inbox, channel: sms_channel) }
      let(:campaign) { build(:campaign, inbox: sms_inbox) }

      include_examples 'polymorphic outbound campaign channel'
    end

    context 'when WhatsApp campaign' do
      let(:account) { create(:account) }
      let(:instance_name) { 'campaign-instance' }
      let(:template) do
        {
          'name' => 'sample_shipping_confirmation',
          'status' => 'APPROVED',
          'category' => 'UTILITY',
          'language' => 'en_US',
          'components' => [
            {
              'text' => 'Your package has been shipped. It will be delivered in {{1}} business days.',
              'type' => 'BODY'
            }
          ],
          'hub_instance_name' => instance_name,
          'hub_opening_enabled' => false,
          'hub_remote_present' => true,
          'hub_remote_available' => true,
          'available' => true,
          'enabled' => true
        }
      end
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          account: account,
          validate_provider_config: false,
          sync_templates: false,
          provider_config: {
            'api_key' => 'test_key',
            'instance_name' => instance_name
          },
          message_templates: [template]
        )
      end
      let(:whatsapp_inbox) { whatsapp_channel.inbox }
      let(:template_params) do
        {
          'name' => template['name'],
          'language' => template['language'],
          'processed_params' => { '1' => '3' }
        }
      end
      let(:campaign) do
        build(
          :campaign,
          inbox: whatsapp_inbox,
          account: account,
          message_attributes: {
            'delivery_mode' => 'template',
            'template_params' => template_params
          }
        )
      end

      include_examples 'polymorphic outbound campaign channel'

      it 'exposes freeform and template capabilities' do
        campaign.save!

        expect(campaign.channel_capabilities).to include('freeform', 'template', 'variables')
      end

      it 'accepts an available campaign template even when it is not enabled for opening conversations' do
        expect(template['hub_opening_enabled']).to be false
        expect(campaign).to be_valid
      end

      it 'allows a freeform campaign without template params' do
        campaign.message_attributes = { 'delivery_mode' => 'freeform' }

        expect(campaign).to be_valid
      end

      it 'allows a freeform recurring campaign without template params' do
        campaign.campaign_type = 'ongoing'
        campaign.message_attributes = { 'delivery_mode' => 'freeform' }
        campaign.save!

        expect(campaign.reload).to be_ongoing
        expect(campaign.scheduled_at).to be_present
        expect(campaign.message_attributes['delivery_mode']).to eq('freeform')
      end

      it 'rejects a template that is not available in the selected Connect|API instance' do
        campaign.message_attributes = {
          'delivery_mode' => 'template',
          'template_params' => template_params.merge('name' => 'unknown_template')
        }

        expect(campaign).not_to be_valid
        expect(campaign.errors[:message_attributes]).to include('selected template is not available for this Connect|API instance')
      end

      it 'dispatches implicit one-off campaigns through the one-off service' do
        campaign_service = double
        expect(Campaigns::OneoffCampaignService).to receive(:new).with(campaign: campaign).and_return(campaign_service)
        expect(campaign_service).to receive(:perform)

        campaign.save!
        campaign.trigger!
      end
    end

    context 'when Email campaign' do
      let(:account) { create(:account) }
      let!(:email_channel) { create(:channel_email, account: account) }
      let(:campaign) do
        build(
          :campaign,
          inbox: email_channel.inbox,
          account: account,
          message_attributes: { 'subject' => 'Campaign subject' }
        )
      end

      include_examples 'polymorphic outbound campaign channel'

      it 'exposes subject capability' do
        campaign.save!
        expect(campaign.channel_capabilities).to include('subject', 'text')
      end

      it 'requires an email subject' do
        campaign.message_attributes = {}

        expect(campaign).not_to be_valid
        expect(campaign.errors[:message_attributes]).to include('subject is required for email campaigns')
      end
    end

    context 'when API webhook campaign' do
      let(:account) { create(:account) }
      let!(:api_channel) { create(:channel_api, account: account, webhook_url: 'https://example.com/hook') }
      let(:campaign) { build(:campaign, inbox: api_channel.inbox, account: account) }

      include_examples 'polymorphic outbound campaign channel'

      it 'exposes webhook capabilities' do
        campaign.save!
        expect(campaign.channel_capabilities).to include('json', 'webhook')
      end

      it 'requires a configured webhook url' do
        api_channel.update!(webhook_url: nil)

        expect(campaign).not_to be_valid
        expect(campaign.errors[:message_attributes]).to include('webhook_url is required for API campaigns')
      end
    end

    context 'when Website campaign' do
      let(:campaign) { build(:campaign) }

      it 'keeps website campaigns recurring by default and scheduled' do
        campaign.save!
        expect(campaign.reload).to be_ongoing
        expect(campaign.scheduled_at).to be_present
      end

      it 'rejects website one-off campaigns instead of silently changing the selected mode' do
        campaign.campaign_type = 'one_off'

        expect(campaign).not_to be_valid
        expect(campaign.errors[:inbox]).to include('Website inbox only supports recurring campaigns')
      end
    end
  end
end
