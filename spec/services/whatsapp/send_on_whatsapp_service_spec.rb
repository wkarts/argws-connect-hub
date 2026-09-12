require 'rails_helper'

describe Whatsapp::SendOnWhatsappService do
  template_params = {
    name: 'sample_shipping_confirmation',
    namespace: '23423423_2342423_324234234_2343224',
    language: 'en_US',
    category: 'Marketing',
    processed_params: { '1' => '3' }
  }

  describe '#perform' do
    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    end

    context 'when a valid message' do
      let(:whatsapp_request) { double }
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          provider: 'default',
          sync_templates: false,
          validate_provider_config: false
        )
      end
      let!(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: '123456789') }
      let!(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: whatsapp_channel.inbox) }

      it 'calls channel.send_message when with in 24 hour limit' do
        create(:message, message_type: :incoming, content: 'test', conversation: conversation)
        message = create(:message, message_type: :outgoing, content: 'test', conversation: conversation)
        allow(HTTParty).to receive(:post).and_return(whatsapp_request)
        allow(whatsapp_request).to receive(:success?).and_return(true)
        allow(whatsapp_request).to receive(:[]).with('messages').and_return([{ 'id' => '123456789' }])
        expect(HTTParty).to receive(:post).with(
          'https://waba.360dialog.io/v1/messages',
          headers: { 'D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json' },
          body: { 'to' => '123456789', 'text' => { 'body' => 'test' }, 'type' => 'text' }.to_json
        )
        described_class.new(message: message).perform
        expect(message.reload.source_id).to eq('123456789')
      end

      it 'calls channel.send_template when after 24 hour limit' do
        message = create(:message, message_type: :outgoing, content: 'Your package has been shipped. It will be delivered in 3 business days.',
                                   conversation: conversation)
        allow(HTTParty).to receive(:post).and_return(whatsapp_request)
        allow(whatsapp_request).to receive(:success?).and_return(true)
        allow(whatsapp_request).to receive(:[]).with('messages').and_return([{ 'id' => '123456789' }])
        expect(HTTParty).to receive(:post).with(
          'https://waba.360dialog.io/v1/messages',
          headers: { 'D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json' },
          body: {
            to: '123456789',
            template: {
              name: 'sample_shipping_confirmation',
              namespace: '23423423_2342423_324234234_2343224',
              language: { 'policy': 'deterministic', 'code': 'en_US' },
              components: [{ 'type': 'body', 'parameters': [{ 'type': 'text', 'text': '3' }] }]
            },
            type: 'template'
          }.to_json
        )
        described_class.new(message: message).perform
        expect(message.reload.source_id).to eq('123456789')
      end

      it 'calls channel.send_template if template_params are present' do
        message = create(:message, additional_attributes: { template_params: template_params },
                                   content: 'Your package will be delivered in 3 business days.', conversation: conversation, message_type: :outgoing)
        allow(HTTParty).to receive(:post).and_return(whatsapp_request)
        allow(whatsapp_request).to receive(:success?).and_return(true)
        allow(whatsapp_request).to receive(:[]).with('messages').and_return([{ 'id' => '123456789' }])
        expect(HTTParty).to receive(:post).with(
          'https://waba.360dialog.io/v1/messages',
          headers: { 'D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json' },
          body: {
            to: '123456789',
            template: {
              name: 'sample_shipping_confirmation',
              namespace: '23423423_2342423_324234234_2343224',
              language: { 'policy': 'deterministic', 'code': 'en_US' },
              components: [{ 'type': 'body', 'parameters': [{ 'type': 'text', 'text': '3' }] }]
            },
            type: 'template'
          }.to_json
        )
        described_class.new(message: message).perform
        expect(message.reload.source_id).to eq('123456789')
      end

      it 'calls channel.send_template when template has regexp characters' do
        message = create(
          :message,
          message_type: :outgoing,
          content: 'عميلنا العزيز الرجاء الرد على هذه الرسالة بكلمة *نعم* للرد على إستفساركم من قبل خدمة العملاء.',
          conversation: conversation
        )
        allow(HTTParty).to receive(:post).and_return(whatsapp_request)
        allow(whatsapp_request).to receive(:success?).and_return(true)
        allow(whatsapp_request).to receive(:[]).with('messages').and_return([{ 'id' => '123456789' }])
        expect(HTTParty).to receive(:post).with(
          'https://waba.360dialog.io/v1/messages',
          headers: { 'D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json' },
          body: {
            to: '123456789',
            template: {
              name: 'customer_yes_no',
              namespace: '2342384942_32423423_23423fdsdaf23',
              language: { 'policy': 'deterministic', 'code': 'ar' },
              components: [{ 'type': 'body', 'parameters': [] }]
            },
            type: 'template'
          }.to_json
        )
        described_class.new(message: message).perform
        expect(message.reload.source_id).to eq('123456789')
      end
    end

    context 'when a Connect API campaign uses freeform text' do
      let!(:whatsapp_channel) do
        create(
          :channel_whatsapp,
          provider: 'connectapi',
          sync_templates: false,
          validate_provider_config: false,
          provider_config: { 'api_key' => 'instance-token', 'instance_name' => 'campaign-instance' },
          message_templates: []
        )
      end
      let!(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: '5575988881111') }
      let!(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: whatsapp_channel.inbox) }
      let!(:campaign) do
        create(
          :campaign,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          message: 'Mensagem livre da campanha',
          message_attributes: { 'delivery_mode' => 'freeform' }
        )
      end

      it 'uses the normal send_message path even outside the reply window' do
        message = create(
          :message,
          account: whatsapp_channel.account,
          inbox: whatsapp_channel.inbox,
          conversation: conversation,
          message_type: :outgoing,
          content: 'Mensagem livre da campanha',
          additional_attributes: { 'campaign_id' => campaign.id }
        )

        allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(false)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_template)
        expect_any_instance_of(Channel::Whatsapp).to receive(:send_message)
          .with('5575988881111', message).and_return('freeform-message-id')

        described_class.new(message: message).perform

        expect(message.reload.source_id).to eq('freeform-message-id')
      end
    end
  end
end
