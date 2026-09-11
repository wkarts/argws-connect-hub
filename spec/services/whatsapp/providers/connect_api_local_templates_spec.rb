require 'rails_helper'

RSpec.describe Whatsapp::Providers::ConnectApiService, 'local templates' do
  let(:remote) do
    {
      'id' => 'lt_fixture', 'name' => 'hello', 'language' => 'pt_BR',
      'source' => 'connectapi_local', 'execution' => 'rendered_text', 'approved' => true,
      'version' => 1, 'enabled' => true, 'available' => true, 'status' => 'APPROVED', 'category' => 'OPENING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Como podemos ajudar?' }]
    }
  end
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', sync_templates: false, validate_provider_config: false,
           provider_config: {
             'api_key' => 'only-instance-token', 'instance_name' => 'local-fixture',
             'phone_number_id' => '5575988881111', 'business_account_id' => '5575988881111',
             'url' => 'https://connect.example/graph'
           })
  end
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:message) do
    double(content: 'Olá! Como podemos ajudar?', content_attributes: {}, additional_attributes: {
      'template_params' => { 'name' => 'hello', 'language' => 'pt_BR', 'connect_api_version' => 1, 'processed_params' => {} }
    })
  end
  before do
    entries = channel.opening_template_catalog.reconcile([remote])
    channel.update_columns(message_templates: entries)
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_REQUEST_TIMEOUT', anything).and_return(60)
    expect(GlobalConfigService).not_to receive(:load).with('CONNECT_API_AUTH_TOKEN', anything)
    allow(message).to receive(:update!)
  end

  it 'sends the template with the scoped Bearer, revision, empty parameter array and real message ID' do
    request = stub_request(:post, 'https://connect.example/graph/v20.0/5575988881111/messages')
              .with(headers: { 'Authorization' => 'Bearer only-instance-token' }, body: hash_including(
                'type' => 'template', 'template' => hash_including('connect_api_version' => 1,
                  'components' => [{ 'type' => 'body', 'parameters' => [] }])
              ))
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: 'REAL_MESSAGE_ID' }] }.to_json)
    expect(service.send_template(message, '5575999999999', name: 'hello', lang_code: 'pt_BR')).to eq('REAL_MESSAGE_ID')
    expect(request).to have_been_requested.once
    expect(message).to have_received(:update!).with(hash_including(source_id: 'REAL_MESSAGE_ID'))
  end

  it 'does not send a stale revision or arbitrary preview content' do
    channel.message_templates[0]['version'] = 2
    expect(HTTParty).not_to receive(:post)
    expect(service.send_template(message, '5575999999999', name: 'hello', lang_code: 'pt_BR')).to be_nil
    expect(message).to have_received(:update!).with(hash_including(status: :failed))
  end

  it 'does not replace the instance token with a global credential' do
    channel.provider_config['api_key'] = ''
    expect(HTTParty).not_to receive(:post)
    expect(service.send_template(message, '5575999999999', name: 'hello', lang_code: 'pt_BR')).to be_nil
    expect(message).to have_received(:update!).with(hash_including(status: :failed))
  end

  it 'does not retry a timeout through a different contract' do
    request = stub_request(:post, 'https://connect.example/graph/v20.0/5575988881111/messages').to_timeout
    expect(service.send_template(message, '5575999999999', name: 'hello', lang_code: 'pt_BR')).to be_nil
    expect(request).to have_been_requested.once
    expect(message).to have_received(:update!).with(hash_including(status: :failed))
  end
end
