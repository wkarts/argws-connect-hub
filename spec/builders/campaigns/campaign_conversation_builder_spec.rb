require 'rails_helper'

describe Campaigns::CampaignConversationBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, identifier: '123') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:campaign) { create(:campaign, inbox: inbox, account: account, trigger_rules: { url: 'https://test.com' }) }

  describe '#perform' do
    it 'creates a conversation with campaign id and message with campaign message' do
      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id
      ).perform

      expect(campaign_conversation.campaign_id).to eq(campaign.id)
      expect(campaign_conversation.messages.first.content).to eq(campaign.message)
      expect(campaign_conversation.messages.first.additional_attributes['campaign_id']).to eq(campaign.id)
    end

    it 'passes polymorphic message attributes to the message builder' do
      template_params = {
        name: 'approved_template',
        language: 'pt_BR',
        processed_params: { '1' => 'Wallace' }
      }

      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id,
        message_attributes: { template_params: template_params }
      ).perform

      message = campaign_conversation.messages.first
      expect(message.additional_attributes['template_params']['name']).to eq('approved_template')
      expect(message.additional_attributes['template_params']['language']).to eq('pt_BR')
    end

    it 'reuses persisted campaign message attributes when delivery does not override them' do
      campaign.update!(
        message_attributes: {
          'template_params' => {
            'name' => 'persisted_template',
            'language' => 'pt_BR',
            'processed_params' => { '1' => 'Cliente' }
          }
        }
      )

      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id
      ).perform

      message = campaign_conversation.messages.first
      expect(message.additional_attributes.dig('template_params', 'name')).to eq('persisted_template')
      expect(message.additional_attributes.dig('template_params', 'processed_params', '1')).to eq('Cliente')
    end

    it 'will not create a conversation with campaign id if another conversation exists' do
      create(:conversation, contact_inbox_id: contact_inbox.id, inbox: inbox, account: account)
      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id
      ).perform

      expect(campaign_conversation).to be_nil
    end

    it 'allows outbound channel campaigns to create a dedicated conversation when another conversation exists' do
      create(:conversation, contact_inbox_id: contact_inbox.id, inbox: inbox, account: account)

      campaign_conversation = described_class.new(
        contact_inbox_id: contact_inbox.id,
        campaign_display_id: campaign.display_id,
        skip_existing_conversation: false
      ).perform

      expect(campaign_conversation).to be_present
      expect(campaign_conversation.campaign_id).to eq(campaign.id)
      expect(contact_inbox.reload.conversations.count).to eq(2)
    end
  end
end
