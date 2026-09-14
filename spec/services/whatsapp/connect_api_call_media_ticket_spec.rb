require 'rails_helper'

RSpec.describe Whatsapp::ConnectApiCallService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'api_key' => 'instance-secret',
        'instance_name' => 'hub-call-media-ticket-test',
        'phone_number_id' => '5575988881111',
        'connect_api_provider' => 'WHATSAPP-ZAPO',
        'calls_supported' => true,
        'voice_supported' => true
      }
    )
  end

  let(:contact_phone) { '5575996236940' }
  let(:call_id) { 'call-media-ticket-1' }
  let(:client) { instance_double(ConnectApi::Client) }
  let(:conversation) do
    Whatsapp::IncomingConnectApiCallService.new(
      channel: whatsapp_channel,
      params: {
        event: 'call',
        instance: 'hub-call-media-ticket-test',
        date_time: '2026-09-14T14:20:00Z',
        data: {
          action: 'state',
          provider: 'WHATSAPP-ZAPO',
          call: {
            callId: call_id,
            direction: 'outgoing',
            displayPeerJid: "#{contact_phone}@s.whatsapp.net",
            status: 'ringing',
            providerState: 'RINGING',
            terminal: false,
            isVideo: false
          }
        }
      }
    ).perform

    whatsapp_channel.inbox.conversations.last
  end

  subject(:service) do
    described_class.new(
      whatsapp_channel: whatsapp_channel,
      contact_phone: conversation.contact.phone_number,
      conversation: conversation,
      client: client
    )
  end

  before do
    allow(GlobalConfigService).to receive(:load)
      .with('CONNECT_API_PUBLIC_URL', anything)
      .and_return('https://connect.example.test')
  end

  it 'requests media directly for the active call already bound to the conversation' do
    expect(client).not_to receive(:list_calls)
    allow(client).to receive(:media_ticket)
      .with('hub-call-media-ticket-test', call_id)
      .and_return(
        {
          'ticket' => 'media-ticket-1',
          'expiresAt' => '2026-09-14T14:20:30Z',
          'expiresInSeconds' => 30,
          'mediaPath' => '/voice/media'
        }
      )

    result = service.media_ticket(call_id)

    expect(client).to have_received(:media_ticket).with('hub-call-media-ticket-test', call_id)
    expect(result).to include(
      ticket: 'media-ticket-1',
      media_url: 'wss://connect.example.test/voice/media'
    )
  end

  it 'does not allow a media ticket for a call that is not active in this conversation' do
    expect(client).not_to receive(:list_calls)
    expect(client).not_to receive(:media_ticket)

    expect { service.media_ticket('another-call-id') }
      .to raise_error(ConnectApi::Error, 'Chamada não encontrada nesta conversa.')
  end
end
