require 'rails_helper'

describe Whatsapp::ConnectApiHistoricalReconciliationService do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'history-instance',
        'api_key' => 'instance-token'
      }
    )
  end
  let!(:contact) { create(:contact, account: channel.account, phone_number: '+557588449231') }
  let!(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '557588449231') }
  let!(:conversation) do
    create(
      :conversation,
      account: channel.account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :resolved,
      created_at: 2.days.ago,
      last_activity_at: 1.day.ago
    )
  end
  let(:client) { instance_double(ConnectApi::Client) }
  let(:service) { described_class.new(channel: channel, client: client, operation_id: 'op-history') }

  before do
    allow(Channels::Whatsapp::ConnectApiProfilePictureJob).to receive(:perform_later)
    allow(HubDiagnostics::Recorder).to receive(:emit)
  end

  it 'imports a missing historical text message without reopening the resolved conversation' do
    timestamp = 12.hours.ago.change(usec: 0)
    record = {
      'key' => {
        'id' => 'HISTORY-TEXT-1',
        'fromMe' => false,
        'remoteJid' => '557588449231@s.whatsapp.net'
      },
      'messageTimestamp' => timestamp.to_i,
      'pushName' => 'Contato Histórico',
      'messageType' => 'conversation',
      'message' => { 'conversation' => 'Mensagem histórica' },
      'MessageUpdate' => []
    }

    result = service.process(record)

    imported = result.message.reload
    expect(imported.source_id).to eq('HISTORY-TEXT-1')
    expect(imported.content).to eq('Mensagem histórica')
    expect(imported.created_at.to_i).to eq(timestamp.to_i)
    expect(imported.conversation_id).to eq(conversation.id)
    expect(conversation.reload).to be_resolved
    expect(conversation.last_activity_at.to_i).to eq(1.day.ago.to_i).or be_within(2).of(1.day.ago.to_i)
  end

  it 'is idempotent by inbox and source id' do
    existing = create(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      source_id: 'HISTORY-EXISTING-1',
      message_type: :incoming
    )
    record = {
      'key' => {
        'id' => 'HISTORY-EXISTING-1',
        'fromMe' => false,
        'remoteJid' => '557588449231@s.whatsapp.net'
      },
      'messageTimestamp' => 1.hour.ago.to_i,
      'messageType' => 'conversation',
      'message' => { 'conversation' => 'Duplicada' },
      'MessageUpdate' => []
    }

    expect { service.process(record) }.not_to change(Message, :count)
    expect(Message.find_by(source_id: existing.source_id).id).to eq(existing.id)
    expect(conversation.reload).to be_resolved
  end
end
