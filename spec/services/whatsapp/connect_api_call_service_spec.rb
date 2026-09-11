require 'rails_helper'

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

  let(:contact_phone) { '557596236940' }
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
    @conversation.messages.delete_all
  end

  def service
    described_class.new(
      whatsapp_channel: whatsapp_channel,
      contact_phone: @conversation.contact.phone_number,
      conversation: @conversation,
      client: client
    )
  end

  it 'creates the timeline item from call list even without depending on a native webhook' do
    allow(client).to receive(:list_calls).with('hub-call-local-test').and_return([raw_call])

    expect { service.list }.to change { @conversation.messages.count }.by(1)

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-local-1')
    expect(message).to be_present
    expect(message.message_type).to eq('activity')
    expect(message.content).to eq('Chamada efetuada')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ringing')
    expect(message.content_attributes.dig('connect_api_call', 'peer_name')).to eq('Cliente Teste')
    expect(message.content_attributes.dig('connect_api_call', 'peer_phone')).to eq(contact_phone)
  end

  it 'creates an outgoing timeline item immediately when the HUB starts a call' do
    allow(client).to receive(:offer_call)
      .with('hub-call-local-test', number: contact_phone, is_video: false, call_duration: nil)
      .and_return({ 'callId' => 'call-offer-1' })

    expect do
      service.offer(number: "+#{contact_phone}", is_video: false)
    end.to change { @conversation.messages.count }.by(1)

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-offer-1')
    expect(message).to be_present
    expect(message.content).to eq('Chamada efetuada')
    expect(message.content_attributes.dig('connect_api_call', 'direction')).to eq('outgoing')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ringing')
  end

  it 'updates the same timeline item when the local call is ended' do
    allow(client).to receive(:list_calls).with('hub-call-local-test').and_return([raw_call])
    service.list

    allow(client).to receive(:end_call)
      .with('hub-call-local-test', 'call-local-1')
      .and_return({ 'callId' => 'call-local-1' })

    expect do
      service.end_call('call-local-1')
    end.not_to change { @conversation.messages.where(source_id: 'connect-api-call:call-local-1').count }

    message = @conversation.messages.find_by(source_id: 'connect-api-call:call-local-1')
    expect(message.reload.content).to eq('Chamada encerrada')
    expect(message.content_attributes.dig('connect_api_call', 'status')).to eq('ended')
    expect(message.content_attributes.dig('connect_api_call', 'terminal')).to be(true)
  end
end
