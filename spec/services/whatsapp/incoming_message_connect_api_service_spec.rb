require 'rails_helper'

describe Whatsapp::IncomingMessageConnectApiService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'api_key' => 'test_key',
        'phone_number_id' => '5575988881111',
        'business_account_id' => '5575988881111'
      }
    )
  end

  let(:peer_phone) { '557596236940' }
  let(:own_phone) { whatsapp_channel.provider_config['phone_number_id'] }

  def webhook(message_id:, from:, body:, profile_name: 'Cliente WhatsApp', profile_picture: nil, from_me: false)
    {
      phone_number: whatsapp_channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          value: {
            metadata: {
              display_phone_number: own_phone,
              phone_number_id: own_phone
            },
            contacts: [{
              profile: {
                name: profile_name,
                picture: profile_picture
              }.compact,
              wa_id: peer_phone
            }],
            messages: [{
              from: from,
              id: message_id,
              timestamp: Time.current.to_i.to_s,
              type: 'text',
              text: { body: body },
              connect_api: {
                from_me: from_me,
                remote_jid: '22654721644999@lid',
                remote_jid_alt: "#{peer_phone}@s.whatsapp.net"
              }
            }]
          }
        }]
      }]
    }.with_indifferent_access
  end

  it 'stores physical-device messages as outgoing and reuses the same active conversation' do
    service = described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(message_id: 'PHONE-OUT-1', from: own_phone, body: 'Enviado pelo celular', from_me: true)
    )
    service.perform

    conversation = whatsapp_channel.inbox.conversations.last
    expect(conversation.messages.last.message_type).to eq('outgoing')
    expect(conversation.messages.last.content).to eq('Enviado pelo celular')
    expect(conversation.messages.last.sender).to be_nil

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(message_id: 'CLIENT-IN-1', from: peer_phone, body: 'Resposta do cliente')
    ).perform

    expect(whatsapp_channel.inbox.conversations.reload.count).to eq(1)
    expect(conversation.reload.messages.last.message_type).to eq('incoming')
    expect(conversation.messages.last.content).to eq('Resposta do cliente')
  end

  it 'refreshes a number-only contact with Connect API push name and profile picture metadata' do
    contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: peer_phone)
    contact_inbox.contact.update!(name: peer_phone, phone_number: "+#{peer_phone}")
    allow(Avatar::AvatarFromUrlJob).to receive(:perform_later)

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'CLIENT-IN-2',
        from: peer_phone,
        body: 'Olá',
        profile_name: 'Mumu',
        profile_picture: 'https://cdn.example/mumu.jpg'
      )
    ).perform

    contact = contact_inbox.contact.reload
    expect(contact.name).to eq('Mumu')
    expect(contact.additional_attributes.dig('connect_api', 'aliases')).to include("#{peer_phone}@s.whatsapp.net")
    expect(Avatar::AvatarFromUrlJob).to have_received(:perform_later).with(contact, 'https://cdn.example/mumu.jpg')
  end

  it 'keeps only the selected active conversation when historical duplicates exist' do
    contact_inbox = create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: peer_phone)
    stale = create(:conversation, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox, status: :open)
    current = create(:conversation, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox, status: :open)

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(message_id: 'CLIENT-IN-3', from: peer_phone, body: 'Continua aqui')
    ).perform

    expect(current.reload.status).to eq('open')
    expect(stale.reload.status).to eq('resolved')
    expect(contact_inbox.conversations.where.not(status: :resolved).count).to eq(1)
  end
end
