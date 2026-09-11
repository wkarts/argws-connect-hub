require 'rails_helper'

describe Whatsapp::IncomingConnectApiCallService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'api_key' => 'instance-secret',
        'instance_name' => 'hub-call-test',
        'phone_number_id' => '5575988881111',
        'connect_api_provider' => 'WHATSAPP-ZAPO'
      }
    )
  end

  def call_payload(status:, action: 'state', call_id: 'call-1', direction: 'incoming', peer: '557596236940@s.whatsapp.net', terminal: false,
                   call_attributes: {})
    {
      event: 'call',
      instance: 'hub-call-test',
      data: {
        action: action,
        provider: 'WHATSAPP-ZAPO',
        call: {
          callId: call_id,
          direction: direction,
          displayPeerJid: peer,
          status: status,
          providerState: status == 'answered' ? 'CONNECTED' : 'OFFER_RECEIVED',
          terminal: terminal,
          isVideo: false
        }.merge(call_attributes)
      }
    }.with_indifferent_access
  end

  it 'creates one activity item for an incoming call and updates it by callId' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(status: 'ringing', action: 'incoming')
    ).perform

    conversation = whatsapp_channel.inbox.conversations.last
    expect(conversation).to be_present

    message = conversation.messages.find_by(source_id: 'connect-api-call:call-1')
    expect(message).to be_present
    expect(message.message_type).to eq('activity')
    expect(message.content).to eq('Chamada recebida')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ringing')
    expect(message.content_attributes.dig('connect_api_call', 'peer_phone')).to eq('5575996236940')

    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(status: 'answered')
    ).perform

    expect(conversation.messages.where(source_id: 'connect-api-call:call-1').count).to eq(1)
    expect(message.reload.content).to eq('Chamada atendida')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('answered')
  end

  it 'normalizes call timestamps and stores the connected duration on the same timeline item' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'ringing',
        action: 'incoming',
        call_attributes: { createdAt: '2026-09-11T03:10:00-03:00' }
      )
    ).perform

    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'answered',
        call_attributes: { answeredAt: '2026-09-11T03:10:10-03:00' }
      )
    ).perform

    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'ended',
        action: 'ended',
        terminal: true,
        call_attributes: { endedAt: '2026-09-11T03:12:10-03:00' }
      )
    ).perform

    message = whatsapp_channel.inbox.messages.find_by(source_id: 'connect-api-call:call-1')
    call = message.content_attributes.fetch('connect_api_call')

    expect(message.content).to eq('Chamada encerrada')
    expect(call['started_at']).to eq('2026-09-11T06:10:00.000Z')
    expect(call['answered_at']).to eq('2026-09-11T06:10:10.000Z')
    expect(call['ended_at']).to eq('2026-09-11T06:12:10.000Z')
    expect(call['duration_seconds']).to eq(120)
  end

  it 'classifies a terminal unknown incoming call as missed instead of updating' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'unknown',
        terminal: true,
        direction: 'incoming',
        call_attributes: {
          providerState: 'ENDED',
          providerReason: 'NO_ANSWER'
        }
      )
    ).perform

    message = whatsapp_channel.inbox.messages.find_by(source_id: 'connect-api-call:call-1')
    expect(message.content).to eq('Chamada perdida')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('missed')
    expect(message.content_attributes.dig('connect_api_call', 'terminal')).to be(true)
  end

  it 'classifies a terminal unknown outgoing call as unanswered instead of updating' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'unknown',
        terminal: true,
        direction: 'outgoing',
        call_attributes: {
          providerState: 'ENDED',
          providerReason: 'TIMEOUT'
        }
      )
    ).perform

    message = whatsapp_channel.inbox.messages.find_by(source_id: 'connect-api-call:call-1')
    expect(message.content).to eq('Chamada não atendida')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('unanswered')
    expect(message.content_attributes.dig('connect_api_call', 'terminal')).to be(true)
  end

  it 'keeps an answered call as ended when a later terminal event has unknown status' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(status: 'answered')
    ).perform

    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(
        status: 'unknown',
        action: 'ended',
        terminal: true,
        call_attributes: { providerState: 'ENDED' }
      )
    ).perform

    message = whatsapp_channel.inbox.messages.find_by(source_id: 'connect-api-call:call-1')
    expect(message.reload.content).to eq('Chamada encerrada')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ended')
  end

  it 'keeps a terminal missed call from regressing to ringing' do
    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(status: 'missed', action: 'ended', terminal: true)
    ).perform

    message = whatsapp_channel.inbox.messages.find_by(source_id: 'connect-api-call:call-1')
    expect(message.content).to eq('Chamada perdida')

    described_class.new(
      channel: whatsapp_channel,
      params: call_payload(status: 'ringing', action: 'state')
    ).perform

    expect(message.reload.content).to eq('Chamada perdida')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('missed')
  end

  it 'does not manufacture a phone number from a LID-only call' do
    expect do
      described_class.new(
        channel: whatsapp_channel,
        params: call_payload(status: 'ringing', action: 'incoming', peer: '22654721644999@lid')
      ).perform
    end.not_to change { whatsapp_channel.inbox.conversations.count }
  end
end

describe Whatsapp::ConnectApiCallService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'api_key' => 'instance-secret',
        'instance_name' => 'hub-call-local-test',
        'phone_number_id' => '5575988881111',
        'connect_api_provider' => 'WHATSAPP-ZAPO',
        'calls_supported' => true,
        'voice_supported' => true
      }
    )
  end

  let(:contact_phone) { '5575996236940' }
  let(:client) { instance_double(ConnectApi::Client) }
  let(:raw_call) do
    {
      'callId' => 'call-local-1',
      'direction' => 'outgoing',
      'status' => 'ringing',
      'providerState' => 'CALLING',
      'displayPeerJid' => "#{contact_phone}@s.whatsapp.net",
      'terminal' => false,
      'isVideo' => false,
      'createdAt' => '2026-09-11T04:00:00-03:00',
      'updatedAt' => '2026-09-11T04:00:00-03:00'
    }
  end

  before do
    Whatsapp::IncomingConnectApiCallService.new(
      channel: whatsapp_channel,
      params: {
        event: 'call',
        data: {
          action: 'incoming',
          provider: 'WHATSAPP-ZAPO',
          call: {
            callId: 'seed-call',
            direction: 'incoming',
            status: 'ringing',
            displayPeerJid: "#{contact_phone}@s.whatsapp.net"
          }
        }
      }
    ).perform

    @conversation = whatsapp_channel.inbox.conversations.last
    @conversation.contact.update!(name: 'Cliente Teste')
    Message.where(conversation_id: @conversation.id).delete_all
  end

  def local_call_service
    described_class.new(
      whatsapp_channel: whatsapp_channel,
      contact_phone: @conversation.contact.phone_number,
      conversation: @conversation,
      client: client
    )
  end

  it 'creates timeline from call list without depending on native webhook delivery' do
    allow(client).to receive(:list_calls).with('hub-call-local-test').and_return([raw_call])

    expect { local_call_service.list }.to change { @conversation.messages.count }.by(1)

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-local-1')
    expect(message).to be_present
    expect(message.content).to eq('Chamada efetuada')
    expect(message.content_attributes.dig('connect_api_call', 'peer_name')).to eq('Cliente Teste')
    expect(message.content_attributes.dig('connect_api_call', 'peer_phone')).to eq(contact_phone)
  end

  it 'creates outgoing timeline immediately when the HUB starts the call' do
    allow(client).to receive(:offer_call)
      .with('hub-call-local-test', number: contact_phone, is_video: false, call_duration: nil)
      .and_return({ 'callId' => 'call-offer-1' })

    expect do
      local_call_service.offer(number: "+#{contact_phone}", is_video: false)
    end.to change { @conversation.messages.count }.by(1)

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-offer-1')
    expect(message.content).to eq('Chamada efetuada')
    expect(message.content_attributes.dig('connect_api_call', 'direction')).to eq('outgoing')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ringing')
  end

  it 'updates the same timeline item when the HUB ends the call' do
    allow(client).to receive(:list_calls).with('hub-call-local-test').and_return([raw_call])
    local_call_service.list

    allow(client).to receive(:end_call)
      .with('hub-call-local-test', 'call-local-1')
      .and_return({ 'callId' => 'call-local-1' })

    expect do
      local_call_service.end_call('call-local-1')
    end.not_to change { @conversation.messages.where(source_id: 'connect-api-call:call-local-1').count }

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-local-1')
    expect(message.reload.content).to eq('Chamada encerrada')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ended')
    expect(message.content_attributes.dig('connect_api_call', 'terminal')).to be(true)
  end
end
