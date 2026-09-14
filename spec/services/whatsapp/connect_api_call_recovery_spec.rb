require 'rails_helper'

describe 'Connect|API call session recovery' do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'api_key' => 'instance-secret',
        'instance_name' => 'hub-call-recovery-test',
        'phone_number_id' => '5575988881111',
        'connect_api_provider' => 'WHATSAPP-ZAPO',
        'calls_supported' => true,
        'voice_supported' => true
      }
    )
  end

  let(:contact_phone) { '5575996236940' }
  let(:call_id) { 'call-recovery-1' }
  let(:client) { instance_double(ConnectApi::Client) }
  let(:raw_call) do
    {
      'callId' => call_id,
      'direction' => 'incoming',
      'status' => 'answered',
      'providerState' => 'CONNECTED',
      'displayPeerJid' => "#{contact_phone}@s.whatsapp.net",
      'terminal' => false,
      'isVideo' => false,
      'createdAt' => '2026-09-13T20:00:00-03:00',
      'updatedAt' => '2026-09-13T20:00:10-03:00'
    }
  end

  def call_payload(status: 'answered', action: 'state', terminal: false)
    {
      event: 'call',
      instance: 'hub-call-recovery-test',
      date_time: '2026-09-13T23:00:10Z',
      data: {
        action: action,
        provider: 'WHATSAPP-ZAPO',
        call: {
          callId: call_id,
          direction: 'incoming',
          displayPeerJid: "#{contact_phone}@s.whatsapp.net",
          status: status,
          providerState: status == 'ended' ? 'ENDED' : 'CONNECTED',
          terminal: terminal,
          isVideo: false
        }
      }
    }
  end

  def call_service(conversation)
    Whatsapp::ConnectApiCallService.new(
      whatsapp_channel: whatsapp_channel,
      contact_phone: conversation.contact.phone_number,
      conversation: conversation,
      client: client
    )
  end

  def create_active_call
    Whatsapp::IncomingConnectApiCallService.new(
      channel: whatsapp_channel,
      params: call_payload
    ).perform

    whatsapp_channel.inbox.conversations.last
  end

  it 'persists the active call id on the conversation and clears it on terminal state' do
    conversation = create_active_call

    state = conversation.reload.additional_attributes.fetch('connect_api_call_state')
    expect(state['active_call_id']).to eq(call_id)
    expect(state['active_status']).to eq('answered')
    expect(state['last_terminal']).to be(false)

    Whatsapp::IncomingConnectApiCallService.new(
      channel: whatsapp_channel,
      conversation: conversation,
      params: call_payload(status: 'ended', action: 'ended', terminal: true)
    ).perform

    state = conversation.reload.additional_attributes.fetch('connect_api_call_state')
    expect(state['active_call_id']).to be_nil
    expect(state['last_call_id']).to eq(call_id)
    expect(state['last_status']).to eq('ended')
    expect(state['last_terminal']).to be(true)
  end

  it 'recovers the persisted call id when end_call is invoked without call_id' do
    conversation = create_active_call

    allow(client).to receive(:list_calls).with('hub-call-recovery-test').and_return([raw_call])
    allow(client).to receive(:end_call)
      .with('hub-call-recovery-test', call_id)
      .and_return({ 'callId' => call_id })

    expect { call_service(conversation).end_call(nil) }.not_to raise_error
    expect(client).to have_received(:end_call).with('hub-call-recovery-test', call_id)

    state = conversation.reload.additional_attributes.fetch('connect_api_call_state')
    expect(state['active_call_id']).to be_nil
    expect(state['last_status']).to eq('ended')
  end

  it 'recovers call_id from the persisted timeline for conversations created before the state pointer patch' do
    conversation = create_active_call
    attributes = conversation.additional_attributes.to_h.deep_stringify_keys.except('connect_api_call_state')
    conversation.update_column(:additional_attributes, attributes)

    allow(client).to receive(:list_calls).with('hub-call-recovery-test').and_return([raw_call])
    allow(client).to receive(:media_ticket)
      .with('hub-call-recovery-test', call_id)
      .and_return(
        {
          'ticket' => 'media-ticket-1',
          'expiresAt' => '2026-09-13T23:05:00Z',
          'expiresInSeconds' => 300,
          'mediaPath' => '/voice/media'
        }
      )
    allow(GlobalConfigService).to receive(:load)
      .with('CONNECT_API_PUBLIC_URL', anything)
      .and_return('https://connect.example.test')

    result = call_service(conversation.reload).media_ticket(nil)

    expect(client).to have_received(:media_ticket).with('hub-call-recovery-test', call_id)
    expect(result[:ticket]).to eq('media-ticket-1')
    expect(result[:media_url]).to eq('wss://connect.example.test/voice/media')
  end

  it 'matches Brazilian mobile calls with legacy ninth-digit and local-number variants' do
    conversation = create_active_call
    legacy_mobile = raw_call.merge(
      'callId' => 'legacy-mobile-call',
      'displayPeerJid' => '557596236940@s.whatsapp.net'
    )
    local_mobile = raw_call.merge(
      'callId' => 'local-mobile-call',
      'displayPeerJid' => '75996236940@s.whatsapp.net'
    )
    unrelated_landline = raw_call.merge(
      'callId' => 'unrelated-landline-call',
      'displayPeerJid' => '557533221122@s.whatsapp.net'
    )

    allow(client).to receive(:list_calls)
      .with('hub-call-recovery-test')
      .and_return([legacy_mobile, local_mobile, unrelated_landline])

    calls = call_service(conversation).list

    expect(calls.map { |call| call['callId'] })
      .to contain_exactly('legacy-mobile-call', 'local-mobile-call')
  end
end
