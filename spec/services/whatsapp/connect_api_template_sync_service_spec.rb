require 'rails_helper'

RSpec.describe Whatsapp::ConnectApiTemplateSyncService do
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', sync_templates: false, validate_provider_config: false,
                             message_templates: [], message_templates_last_updated: nil,
                             provider_config: { 'api_key' => 'instance-token', 'instance_name' => 'hub-test',
                                                'phone_number_id' => '123', 'business_account_id' => '123',
                                                'url' => 'https://connect.example/graph' })
  end
  let(:service) { described_class.new(channel) }
  let(:url) { 'https://connect.example/graph/v14.0/123/message_templates' }
  let(:hello) do
    { 'name' => 'hello', 'language' => 'pt_BR', 'id' => 'real-id', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Texto da API, sem substituição' }] }
  end
  let(:other) { hello.merge('name' => 'aviso', 'id' => 'another-id') }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_REQUEST_TIMEOUT', anything).and_return(60)
  end

  def api_response(payload = nil, success: true, code: 200, **fields)
    payload = fields unless fields.empty?
    double(success?: success, parsed_response: payload, code: code)
  end

  def seed_catalog
    channel.update_columns(message_templates: channel.opening_template_catalog.reconcile([hello, other]),
                           message_templates_last_updated: 1.hour.ago)
    channel.reload
  end

  it 'imports actual content with instance authentication and only enables exact hello' do
    expect(HTTParty).to receive(:get).with(url, headers: { 'Authorization' => 'Bearer instance-token', 'Content-Type' => 'application/json' },
                                              timeout: 60, follow_redirects: false).and_return(api_response('data' => [hello, other]))
    service.sync!
    expect(channel.reload.opening_template_catalog.available_templates(opening_only: true).pluck('name')).to eq(['hello'])
    expect(channel.message_templates.first.slice(*hello.keys)).to eq(hello)
    expect(channel.message_templates_last_updated).to be_present
  end

  it 'preserves preferences and does not provision webhooks during toggling' do
    seed_catalog
    expect(Whatsapp::ConnectApiWebhookSetupService).not_to receive(:new)
    service.set_enabled!(name: 'hello', language: 'pt_BR', enabled: false)
    service.set_enabled!(name: 'aviso', language: 'pt_BR', enabled: true)
    allow(HTTParty).to receive(:get).and_return(api_response('data' => [hello.merge('id' => 'changed-id'), other]))
    service.sync!
    expect(channel.reload.opening_template_catalog.available_templates(opening_only: true).pluck('name')).to eq(['aviso'])
  end

  it 'merges preferences written while the remote request is running' do
    seed_catalog
    allow(HTTParty).to receive(:get) do
      described_class.new(Channel::Whatsapp.find(channel.id)).set_enabled!(name: 'hello', language: 'pt_BR', enabled: false)
      api_response('data' => [hello, other])
    end
    service.sync!
    expect(channel.reload.message_templates.find { |item| item['name'] == 'hello' }['hub_opening_enabled']).to be(false)
  end

  it 'reads all pages before marking missing entries and strips query credentials' do
    next_url = "#{url}?after=next&access_token=do-not-use"
    expect(HTTParty).to receive(:get).with(url, anything).ordered.and_return(api_response('data' => [hello], 'paging' => { 'next' => next_url }))
    expect(HTTParty).to receive(:get).with("#{url}?after=next", anything).ordered.and_return(api_response('data' => [other]))
    service.sync!
    expect(channel.reload.message_templates.pluck('name')).to eq(%w[hello aviso])
  end

  it 'preserves all catalog entries and success timestamp if a later page fails' do
    seed_catalog
    original = channel.message_templates.deep_dup
    timestamp = channel.message_templates_last_updated
    allow(HTTParty).to receive(:get).with(url, anything).and_return(api_response('data' => [hello], 'paging' => { 'next' => "#{url}?after=x" }))
    allow(HTTParty).to receive(:get).with("#{url}?after=x", anything).and_return(api_response({}, success: false, code: 503))
    expect { service.sync! }.to raise_error(described_class::Error, /HTTP 503/)
    expect(channel.reload.message_templates).to eq(original)
    expect(channel.message_templates_last_updated).to eq(timestamp)
  end

  [nil, {}, { 'error' => { 'message' => 'failure' }, 'data' => [] }, { 'data' => [{}] }].each do |payload|
    it "preserves the last valid catalog on malformed payload #{payload.inspect}" do
      seed_catalog
      original = channel.message_templates.deep_dup
      allow(HTTParty).to receive(:get).and_return(api_response(payload))
      expect { service.sync! }.to raise_error(described_class::Error)
      expect(channel.reload.message_templates).to eq(original)
    end
  end

  it 'marks missing templates unavailable without discarding admin preferences or creating hello' do
    seed_catalog
    service.set_enabled!(name: 'aviso', language: 'pt_BR', enabled: true)
    allow(HTTParty).to receive(:get).and_return(api_response('data' => []))
    service.sync!
    expect(channel.reload.opening_template_catalog.available_templates).to be_empty
    expect(channel.message_templates.find { |item| item['name'] == 'aviso' }['hub_opening_enabled']).to be(true)
    allow(HTTParty).to receive(:get).and_return(api_response('data' => [other]))
    service.sync!
    expect(channel.reload.opening_template_catalog.available_templates(opening_only: true).pluck('name')).to eq(['aviso'])
  end

  ['https://evil.example/graph/v14.0/123/message_templates', 'https://connect.example/graph/v14.0/456/message_templates'].each do |next_url|
    it "rejects pagination outside this instance: #{next_url}" do
      expect(HTTParty).to receive(:get).once.and_return(api_response('data' => [hello], 'paging' => { 'next' => next_url }))
      expect { service.sync! }.to raise_error(described_class::Error, /fora do catálogo/)
      expect(channel.reload.message_templates).to be_empty
    end
  end

  it 'rejects a result if the configured instance changed during the request' do
    allow(HTTParty).to receive(:get) do
      channel.class.find(channel.id).update_columns(provider_config: channel.provider_config.merge('instance_name' => 'different'))
      api_response('data' => [hello])
    end
    expect { service.sync! }.to raise_error(described_class::Error, /mudou/)
    expect(channel.reload.message_templates).to be_empty
  end

  it 'does not overwrite a newer completed reconciliation' do
    allow(HTTParty).to receive(:get) do
      channel.class.find(channel.id).update_columns(message_templates_last_updated: 1.minute.from_now)
      api_response('data' => [hello])
    end
    service.sync!
    expect(channel.reload.message_templates).to be_empty
  end

  it 'reports timeouts without changing the last good state' do
    seed_catalog
    original = channel.message_templates.deep_dup
    allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)
    expect { service.sync! }.to raise_error(described_class::Error, /Tempo esgotado/)
    expect(channel.reload.message_templates).to eq(original)
  end
end
