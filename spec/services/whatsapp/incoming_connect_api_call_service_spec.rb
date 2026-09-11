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
    expect(message.content_attributes.dig('connect_api_call', 'peer_phone')).to eq('557596236940')

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
