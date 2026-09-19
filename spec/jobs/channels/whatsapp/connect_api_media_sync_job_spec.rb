require 'rails_helper'

require 'base64'

describe Channels::Whatsapp::ConnectApiMediaSyncJob do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'hub-test-instance',
        'phone_number_id' => '5575988881111'
      }
    )
  end
  let!(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '557588449231') }
  let!(:conversation) { create(:conversation, inbox: channel.inbox, contact_inbox: contact_inbox, status: :open) }
  let(:client) { instance_double(ConnectApi::Client) }
  let(:native_record) do
    {
      'key' => {
        'id' => 'MEDIA-SYNC-1',
        'fromMe' => false,
        'remoteJid' => '557588449231@s.whatsapp.net'
      },
      'messageTimestamp' => Time.current.to_i,
      'pushName' => 'Contato Teste',
      'messageType' => 'audioMessage',
      # findMessages intentionally exposes only the sanitized media shape.
      'message' => {
        'audioMessage' => {
          'seconds' => 3
        }
      }
    }
  end

  before do
    allow(ConnectApi::Client).to receive(:new).and_return(client)
    allow(Channels::Whatsapp::ConnectApiProfilePictureJob).to receive(:perform_later)
  end

  it 'repairs an existing message using only key.id even when findMessages returns sanitized media' do
    message = conversation.messages.create!(
      account_id: channel.account_id,
      inbox_id: channel.inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      source_id: 'MEDIA-SYNC-1'
    )

    allow(client).to receive(:request) do |method, path, **options|
      if method == :post && path.include?('/chat/findMessages/')
        { 'messages' => { 'records' => [native_record] } }
      elsif method == :post && path.include?('/chat/getBase64FromMediaMessage/')
        expect(options[:body]).to eq(
          message: { key: { id: 'MEDIA-SYNC-1' } },
          convertToMp4: false
        )
        {
          'mediaType' => 'audio',
          'fileName' => 'voice.ogg',
          'mimetype' => 'audio/ogg; codecs=opus',
          'base64' => Base64.strict_encode64('voice-bytes')
        }
      else
        raise "Unexpected request #{method} #{path}"
      end
    end

    described_class.perform_now(channel.id)

    message.reload
    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file_type).to eq('audio')
    expect(message.attachments.first.file.download).to eq('voice-bytes')
  end
end
