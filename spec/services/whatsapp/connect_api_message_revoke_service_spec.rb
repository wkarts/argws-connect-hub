require 'rails_helper'

RSpec.describe Whatsapp::ConnectApiMessageRevokeService do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'instance_name' => 'revoke-instance',
        'api_key' => 'instance-token',
        'connect_api_binding_mode' => 'existing'
      }
    )
  end
  let(:contact) do
    create(
      :contact,
      account: channel.account,
      name: 'Contato',
      phone_number: '+5575999999999'
    )
  end
  let(:contact_inbox) do
    create(
      :contact_inbox,
      contact: contact,
      inbox: channel.inbox,
      source_id: '5575999999999'
    )
  end
  let(:conversation) do
    create(
      :conversation,
      account: channel.account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: contact_inbox
    )
  end
  let(:message) do
    create(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: false,
      source_id: 'MSG-REMOTE-1',
      content: 'Mensagem enviada'
    )
  end
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    allow(HubDiagnostics::Recorder).to receive(:emit)
    allow(HubDiagnostics::Recorder).to receive(:error)
  end

  it 'uses the persisted provider message key and revokes it for everyone' do
    expect(client).to receive(:request).with(
      :post,
      '/chat/findMessages/revoke-instance',
      body: {
        where: { key: { id: 'MSG-REMOTE-1' } },
        page: 1,
        offset: 1
      },
      timeout: 10
    ).and_return(
      'messages' => {
        'total' => 1,
        'pages' => 1,
        'currentPage' => 1,
        'records' => [{
          'key' => {
            'id' => 'MSG-REMOTE-1',
            'fromMe' => true,
            'remoteJid' => '5575999999999@s.whatsapp.net'
          }
        }]
      }
    )

    expect(client).to receive(:request).with(
      :delete,
      '/chat/deleteMessageForEveryone/revoke-instance',
      body: {
        id: 'MSG-REMOTE-1',
        fromMe: true,
        remoteJid: '5575999999999@s.whatsapp.net'
      },
      timeout: 20
    ).and_return('status' => 'ok')

    expect(described_class.new(message: message, client: client).perform!).to be(true)
  end

  it 'falls back to the conversation phone jid when provider lookup is unavailable' do
    allow(client).to receive(:request)
      .with(
        :post,
        '/chat/findMessages/revoke-instance',
        body: hash_including(where: { key: { id: 'MSG-REMOTE-1' } }),
        timeout: 10
      )
      .and_raise(ConnectApi::Error.new('not found', status: 404))

    expect(client).to receive(:request).with(
      :delete,
      '/chat/deleteMessageForEveryone/revoke-instance',
      body: {
        id: 'MSG-REMOTE-1',
        fromMe: true,
        remoteJid: '5575999999999@s.whatsapp.net'
      },
      timeout: 20
    ).and_return('status' => 'ok')

    expect(described_class.new(message: message, client: client).perform!).to be(true)
  end

  it 'does not revoke a provider message that is not owned by this account' do
    allow(client).to receive(:request)
      .with(
        :post,
        '/chat/findMessages/revoke-instance',
        body: anything,
        timeout: 10
      )
      .and_return(
        'records' => [{
          'key' => {
            'id' => 'MSG-REMOTE-1',
            'fromMe' => false,
            'remoteJid' => '5575999999999@s.whatsapp.net'
          }
        }]
      )

    expect(client).not_to receive(:request).with(
      :delete,
      '/chat/deleteMessageForEveryone/revoke-instance',
      anything
    )

    expect do
      described_class.new(message: message, client: client).perform!
    end.to raise_error(
      described_class::Error,
      /não foi enviada por esta conta/
    )
  end

  it 'fails closed when Connect API rejects the revoke' do
    allow(client).to receive(:request)
      .with(
        :post,
        '/chat/findMessages/revoke-instance',
        body: anything,
        timeout: 10
      )
      .and_return(
        'records' => [{
          'key' => {
            'id' => 'MSG-REMOTE-1',
            'fromMe' => true,
            'remoteJid' => '5575999999999@s.whatsapp.net'
          }
        }]
      )

    allow(client).to receive(:request)
      .with(
        :delete,
        '/chat/deleteMessageForEveryone/revoke-instance',
        body: anything,
        timeout: 20
      )
      .and_raise(ConnectApi::Error.new('rejected', status: 422))

    expect do
      described_class.new(message: message, client: client).perform!
    end.to raise_error(
      described_class::Error,
      /WhatsApp recusou a exclusão/
    )
  end

  it 'does not apply revoke to incoming or unsent messages' do
    incoming = build(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'INCOMING-1'
    )
    unsent = build(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: nil
    )

    expect(described_class.applicable?(incoming)).to be(false)
    expect(described_class.applicable?(unsent)).to be(false)
  end
end
