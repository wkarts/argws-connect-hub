require 'rails_helper'

require 'base64'

describe Whatsapp::Providers::ConnectApiService do
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'api_key' => 'instance-token',
        'instance_name' => 'hub-test-instance',
        'phone_number_id' => '5575988881111',
        'business_account_id' => '5575988881111',
        'url' => 'https://connect.example/graph'
      }
    )
  end

  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_BASE_URL', anything).and_return('https://connect.example')
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_AUTH_TOKEN', anything).and_return('global-key')
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_REQUEST_TIMEOUT', anything).and_return(60)
  end

  it 'uses the instance token only for Graph-compatible resources' do
    expect(service.api_headers).to eq(
      'Authorization' => 'Bearer instance-token',
      'Content-Type' => 'application/json'
    )
  end

  it 'sends text through the native Connect API endpoint using the installation apikey' do
    message = double(attachments: [], content: 'Olá pelo HUB', sender_name: nil, content_type: 'text')
    allow(message).to receive(:update!)

    response = double(success?: true, parsed_response: { 'key' => { 'id' => 'MSG-1' } })
    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq('https://connect.example/message/sendText/hub-test-instance')
      expect(options[:headers]).to eq(
        'apikey' => 'global-key',
        'Content-Type' => 'application/json'
      )
      expect(JSON.parse(options[:body])).to eq(
        'number' => '557596236940',
        'text' => 'Olá pelo HUB'
      )
      response
    end

    expect(service.send_message('+55 (75) 9623-6940', message)).to eq('MSG-1')
  end

  it 'sends files through the native media endpoint' do
    file = double(attached?: true, filename: 'arquivo.pdf', content_type: 'application/pdf')
    attachment = double(file_type: 'file', download_url: 'https://hub.example/file.pdf', file: file)
    message = double(attachments: [attachment], content: 'Documento', content_type: 'text')
    allow(message).to receive(:update!)

    response = double(success?: true, parsed_response: { 'key' => { 'id' => 'MEDIA-1' } })
    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq('https://connect.example/message/sendMedia/hub-test-instance')
      expect(options[:headers]['apikey']).to eq('global-key')
      expect(JSON.parse(options[:body])).to include(
        'number' => '557596236940',
        'mediatype' => 'document',
        'media' => 'https://hub.example/file.pdf',
        'fileName' => 'arquivo.pdf',
        'mimetype' => 'application/pdf',
        'caption' => 'Documento'
      )
      response
    end

    expect(service.send_message('557596236940', message)).to eq('MEDIA-1')
  end

  it 'sends voice/audio through the native WhatsApp audio endpoint' do
    attachment = double(file_type: 'audio', download_url: 'https://hub.example/audio.ogg')
    message = double(attachments: [attachment], content: nil, content_type: 'text')
    allow(message).to receive(:update!)

    response = double(success?: true, parsed_response: { 'key' => { 'id' => 'AUDIO-1' } })
    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq('https://connect.example/message/sendWhatsAppAudio/hub-test-instance')
      expect(JSON.parse(options[:body])).to eq(
        'number' => '557596236940',
        'audio' => 'https://hub.example/audio.ogg'
      )
      response
    end

    expect(service.send_message('557596236940', message)).to eq('AUDIO-1')
  end

  it 'retries native media delivery as base64 when Connect API cannot fetch the HUB URL' do
    file = double(
      attached?: true,
      filename: 'arquivo.pdf',
      content_type: 'application/pdf',
      download: 'pdf-binary-content'
    )
    attachment = double(file_type: 'file', download_url: 'https://hub.example/file.pdf', file: file)
    message = double(attachments: [attachment], content: 'Documento', content_type: 'text')
    allow(message).to receive(:update!)

    failed = double(success?: false, parsed_response: { 'message' => 'media fetch failed' }, body: 'media fetch failed', code: 400)
    success = double(success?: true, parsed_response: { 'key' => { 'id' => 'MEDIA-BASE64-1' } })
    calls = []
    allow(HTTParty).to receive(:post) do |url, options|
      calls << [url, JSON.parse(options[:body])]
      calls.length == 1 ? failed : success
    end

    expect(service.send_message('557596236940', message)).to eq('MEDIA-BASE64-1')
    expect(calls.length).to eq(2)
    expect(calls.first.last['media']).to eq('https://hub.example/file.pdf')
    expect(calls.last.last['media']).to eq(Base64.strict_encode64('pdf-binary-content'))
    expect(calls.last.last['mimetype']).to eq('application/pdf')
    expect(calls.last.last['fileName']).to eq('arquivo.pdf')
  end
end
