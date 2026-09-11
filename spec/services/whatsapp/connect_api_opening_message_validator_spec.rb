require 'rails_helper'

RSpec.describe Whatsapp::ConnectApiOpeningMessageValidator do
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', sync_templates: false, validate_provider_config: false,
                             message_templates: [], provider_config: { 'api_key' => 'test', 'instance_name' => 'hub-test' })
  end
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let(:hello) { { 'name' => 'hello', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Real' }] } }
  let(:template_params) { { 'name' => 'hello', 'language' => 'pt_BR', 'processed_params' => {} } }
  let(:message) do
    build(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing,
                    additional_attributes: { 'template_params' => template_params })
  end

  before { channel.update_columns(message_templates: channel.opening_template_catalog.reconcile([hello])) }

  it 'allows only a discovered enabled available template for the first outbound message' do
    expect { described_class.new(message).validate! }.not_to raise_error
    message.additional_attributes = {}
    expect { described_class.new(message).validate! }.to raise_error(described_class::Error)
  end

  it 'blocks an unknown name or language even when sent directly to the backend' do
    message.additional_attributes['template_params']['language'] = 'en_US'
    expect { described_class.new(message).validate! }.to raise_error(described_class::Error)
  end

  it 'validates before MessageBuilder saves a free-text opener' do
    user = create(:user, account: channel.account)
    expect { Messages::MessageBuilder.new(user, conversation, { content: 'Free text', message_type: 'outgoing' }).perform }
      .to raise_error(ActiveRecord::RecordInvalid, /template habilitado/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'revalidates persisted choices immediately before sending a queued template' do
    message.save!
    Whatsapp::ConnectApiTemplateSyncService.new(channel).set_enabled!(name: 'hello', language: 'pt_BR', enabled: false)
    expect_any_instance_of(Whatsapp::Providers::ConnectApiService).not_to receive(:send_template)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to include('template habilitado')
  end

  it 'does not allow failed or queued openers to authorize a free-text fallback' do
    create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing,
                     status: :failed, source_id: nil)
    message.additional_attributes = {}
    expect { described_class.new(message).validate! }.to raise_error(described_class::Error)
  end

  it 'preserves free-text replies after a public incoming message' do
    create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :incoming)
    message.additional_attributes = {}
    expect { described_class.new(message).validate! }.not_to raise_error
  end

  it 'preserves free-text replies after a successfully sent opener' do
    create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing,
                     source_id: 'remote-id', status: :sent)
    message.additional_attributes = {}
    expect { described_class.new(message).validate! }.not_to raise_error
  end

  it 'ignores private notes and legacy Meta channels' do
    message.additional_attributes = {}
    message.private = true
    expect { described_class.new(message).validate! }.not_to raise_error
    message.private = false
    channel.update_columns(provider: 'whatsapp_cloud')
    message.inbox.channel.reload
    expect { described_class.new(message).validate! }.not_to raise_error
  end

  it 'blocks a previously enabled template when reconciliation marks it missing' do
    channel.update_columns(message_templates: channel.opening_template_catalog.reconcile([]))
    expect { described_class.new(message).validate! }.to raise_error(described_class::Error)
  end
end
