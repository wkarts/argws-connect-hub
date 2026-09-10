require 'rails_helper'

require 'base64'

describe Whatsapp::IncomingMessageConnectApiService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'api_key' => 'test_key',
        'instance_name' => 'hub-test-instance',
        'phone_number_id' => '5575988881111',
        'business_account_id' => '5575988881111'
      }
    )
  end

  let(:peer_phone) { '557596236940' }
  let(:own_phone) { whatsapp_channel.provider_config['phone_number_id'] }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_BASE_URL', anything).and_return('https://connect.example')
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_AUTH_TOKEN', anything).and_return('global-key')
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_REQUEST_TIMEOUT', anything).and_return(60)
  end

  def webhook(message_id:, from:, body: nil, profile_name: 'Cliente WhatsApp', profile_picture: nil, from_me: false, source: nil,
              include_context: true, type: 'text', media: nil)
    message = {
      from: from,
      id: message_id,
      timestamp: Time.current.to_i.to_s,
      type: type
    }
    if type == 'text'
      message[:text] = { body: body }
    else
      message[type.to_sym] = media || { id: message_id, mime_type: 'application/octet-stream' }
    end
    if include_context
      message[:connect_api] = {
        from_me: from_me,
        remote_jid: '22654721644999@lid',
        remote_jid_alt: "#{peer_phone}@s.whatsapp.net",
        source: source
      }.compact
    end

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
            messages: [message]
          }
        }]
      }]
    }.with_indifferent_access
  end

  def stub_native_audio(message_id:, from_me: false, source: nil, bytes: 'voice-bytes')
    media_response = double(
      success?: true,
      code: 201,
      body: '',
      parsed_response: {
        'mediaType' => 'audio',
        'fileName' => "#{message_id}.ogg",
        'mimetype' => 'audio/ogg; codecs=opus',
        'base64' => Base64.strict_encode64(bytes),
        'fromMe' => from_me,
        'source' => source
      }.compact
    )

    allow(HTTParty).to receive(:post) do |url, options|
      if url.include?('/chat/getBase64FromMediaMessage/')
        request_body = JSON.parse(options.fetch(:body))
        expect(request_body['message']).to eq('key' => { 'id' => message_id })
        expect(request_body['convertToMp4']).to be(false)
        media_response
      elsif url.include?('/chat/findMessages/')
        raise 'Media download must not depend on the sanitized findMessages payload'
      else
        raise "Unexpected POST #{url}"
      end
    end
  end

  it 'stores physical-device messages as outgoing and reuses the same active conversation' do
    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'PHONE-OUT-1',
        from: own_phone,
        body: 'Enviado pelo celular',
        from_me: true,
        source: 'android'
      )
    ).perform

    conversation = whatsapp_channel.inbox.conversations.last
    message = conversation.messages.last
    expect(message.message_type).to eq('outgoing')
    expect(message.content).to eq('Enviado pelo celular')
    expect(message.sender).to be_nil
    expect(message.content_attributes['connect_api_external_outgoing']).to be(true)
    expect(message.content_attributes['connect_api_origin']).to eq('external')
    expect(message.content_attributes['connect_api_source']).to eq('android')
    expect(message.content_attributes['connect_api_replied_outside_hub']).to be(true)

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(message_id: 'CLIENT-IN-1', from: peer_phone, body: 'Resposta do cliente')
    ).perform

    expect(whatsapp_channel.inbox.conversations.reload.count).to eq(1)
    expect(conversation.reload.messages.last.message_type).to eq('incoming')
    expect(conversation.messages.last.content).to eq('Resposta do cliente')
  end

  it 'reconciles fromMe through the native message repository when the Meta webhook omits direction metadata' do
    native_response = double(
      success?: true,
      parsed_response: {
        'messages' => {
          'records' => [{
            'key' => {
              'id' => 'PHONE-OUT-LEGACY',
              'fromMe' => true,
              'remoteJid' => '22654721644999@lid',
              'remoteJidAlt' => "#{peer_phone}@s.whatsapp.net"
            },
            'source' => 'android',
            'pushName' => 'Cliente salvo'
          }]
        }
      }
    )
    allow(HTTParty).to receive(:post).and_return(native_response)

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'PHONE-OUT-LEGACY',
        from: peer_phone,
        body: 'Resposta fora do HUB',
        include_context: false
      )
    ).perform

    message = whatsapp_channel.inbox.conversations.last.messages.last
    expect(message.message_type).to eq('outgoing')
    expect(message.sender).to be_nil
    expect(message.content_attributes['connect_api_external_outgoing']).to be(true)
    expect(message.content_attributes['connect_api_source']).to eq('android')
  end

  it 'marks Connect API generated external replies as bot-originated' do
    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'BOT-OUT-1',
        from: own_phone,
        body: 'Mensagem automática',
        from_me: true,
        source: 'api'
      )
    ).perform

    message = whatsapp_channel.inbox.conversations.last.messages.last
    expect(message.message_type).to eq('outgoing')
    expect(message.content_attributes['connect_api_external_outgoing']).to be(true)
    expect(message.content_attributes['connect_api_origin']).to eq('bot')
    expect(message.content_attributes['connect_api_source']).to eq('api')
  end

  it 'downloads incoming media from the signed storage URL without forwarding OAuth headers' do
    descriptor = double(
      success?: true,
      code: 200,
      body: '',
      parsed_response: { 'url' => 'https://storage.example/signed/audio.ogg' }
    )
    downloaded = double('downloaded-file')
    allow(HTTParty).to receive(:get).and_return(descriptor)
    allow(Down).to receive(:download).with('https://storage.example/signed/audio.ogg').and_return(downloaded)

    service = described_class.new(inbox: whatsapp_channel.inbox, params: webhook(message_id: 'MEDIA-1', from: peer_phone, body: 'x'))
    result = service.send(:download_attachment_file, { id: 'MEDIA-1' }.with_indifferent_access)

    expect(result).to eq(downloaded)
    expect(Down).to have_received(:download).with('https://storage.example/signed/audio.ogg')
  end

  it 'recovers incoming audio by message key when Graph media is unavailable' do
    descriptor = double(success?: false, code: 500, body: 'descriptor unavailable')
    allow(HTTParty).to receive(:get).and_return(descriptor)
    stub_native_audio(message_id: 'AUDIO-IN-1')

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'AUDIO-IN-1',
        from: peer_phone,
        type: 'audio',
        media: { id: 'AUDIO-IN-1', mime_type: 'audio/ogg; codecs=opus' }
      )
    ).perform

    message = whatsapp_channel.inbox.conversations.last.messages.last
    expect(message.message_type).to eq('incoming')
    expect(message.attachments.count).to eq(1)
    attachment = message.attachments.first
    expect(attachment.file_type).to eq('audio')
    expect(attachment.file.filename.to_s).to eq('AUDIO-IN-1.ogg')
    expect(attachment.file.download).to eq('voice-bytes')
  end

  it 'recovers audio sent outside HUB and keeps it marked as an external outgoing reply' do
    descriptor = double(success?: false, code: 500, body: 'descriptor unavailable')
    allow(HTTParty).to receive(:get).and_return(descriptor)
    stub_native_audio(message_id: 'AUDIO-OUT-1', from_me: true, source: 'android', bytes: 'mobile-voice')

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'AUDIO-OUT-1',
        from: own_phone,
        from_me: true,
        source: 'android',
        type: 'audio',
        media: { id: 'AUDIO-OUT-1', mime_type: 'audio/ogg; codecs=opus' }
      )
    ).perform

    message = whatsapp_channel.inbox.conversations.last.messages.last
    expect(message.message_type).to eq('outgoing')
    expect(message.sender).to be_nil
    expect(message.attachments.first.file_type).to eq('audio')
    expect(message.attachments.first.file.download).to eq('mobile-voice')
    expect(message.content_attributes['connect_api_external_outgoing']).to be(true)
    expect(message.content_attributes['connect_api_replied_outside_hub']).to be(true)
    expect(message.content_attributes['connect_api_source']).to eq('android')
  end

  it 'uses the webhook MIME type when the provider returns only a logical media type' do
    descriptor = double(success?: false, code: 500, body: 'descriptor unavailable')
    allow(HTTParty).to receive(:get).and_return(descriptor)
    media_response = double(
      success?: true,
      code: 201,
      body: '',
      parsed_response: {
        'mediaType' => 'audio',
        'fileName' => 'AUDIO-MIME-1.ogg',
        'base64' => Base64.strict_encode64('voice-without-native-mime')
      }
    )
    allow(HTTParty).to receive(:post).and_return(media_response)

    described_class.new(
      inbox: whatsapp_channel.inbox,
      params: webhook(
        message_id: 'AUDIO-MIME-1',
        from: peer_phone,
        type: 'audio',
        media: { id: 'AUDIO-MIME-1', mime_type: 'audio/ogg; codecs=opus' }
      )
    ).perform

    attachment = whatsapp_channel.inbox.conversations.last.messages.last.attachments.first
    expect(attachment.file.blob.content_type).to start_with('audio/ogg')
    expect(attachment.file.download).to eq('voice-without-native-mime')
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
