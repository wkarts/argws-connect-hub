require 'rails_helper'

describe Channels::Whatsapp::ConnectApiReceiptWatchJob do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'receipt-instance',
        'api_key' => 'instance-token'
      }
    )
  end
  let!(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5575999999999') }
  let!(:conversation) { create(:conversation, inbox: channel.inbox, contact_inbox: contact_inbox) }
  let!(:message) do
    create(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :outgoing,
      status: :progress,
      source_id: 'MSG-RECEIPT-1'
    )
  end
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    allow(ConnectApi::Client).to receive(:new).and_return(client)
    allow(HubDiagnostics::Recorder).to receive(:emit)
  end

  it 'applies the best persisted receipt immediately' do
    allow(client).to receive(:request).with(
      :post,
      '/chat/findStatusMessage/receipt-instance',
      body: { where: { id: 'MSG-RECEIPT-1' }, page: 1, offset: 50 },
      timeout: 10
    ).and_return([
      { 'status' => 'SERVER_ACK' },
      { 'status' => 'DELIVERY_ACK' },
      { 'status' => 'READ' }
    ])

    described_class.perform_now(message.id, 0)

    expect(message.reload.status).to eq('read')
  end

  it 'does not regress a read message' do
    message.update!(status: :read)
    expect(client).not_to receive(:request)

    described_class.perform_now(message.id, 0)

    expect(message.reload.status).to eq('read')
  end
end
