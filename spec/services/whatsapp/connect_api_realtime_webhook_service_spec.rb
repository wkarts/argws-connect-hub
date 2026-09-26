require 'rails_helper'

RSpec.describe Whatsapp::ConnectApiRealtimeWebhookService do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988449231',
      provider_config: {
        'instance_name' => 'hub-realtime-instance',
        'phone_number_id' => '5575988449231'
      }
    )
  end
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    allow(ConnectApi::Client).to receive(:new).and_return(client)
    allow(HubDiagnostics::Recorder).to receive(:emit)
    allow(HubDiagnostics::Recorder).to receive(:error)
  end

  it 'keeps a healthy realtime webhook unchanged' do
    allow(client).to receive(:request).with(
      :get,
      '/compat/meta/hub-realtime-instance',
      timeout: 10
    ).and_return(
      'enabled' => true,
      'phoneNumberId' => '5575988449231',
      'displayPhoneNumber' => '+55 75 98844-9231',
      'webhookUrl' => 'http://localhost:3000/webhooks/whatsapp/5575988449231'
    )

    expect(client).not_to receive(:request).with(:put, anything, anything)

    expect(described_class.new(channel: channel).ensure!).to eq(:ok)
  end

  it 'repairs a missing or stale realtime webhook without recreating the instance' do
    get_count = 0
    allow(client).to receive(:request) do |method, path, **options|
      expect(path).to eq('/compat/meta/hub-realtime-instance')
      if method == :get
        get_count += 1
        {
          'enabled' => true,
          'phoneNumberId' => '5575988449231',
          'businessAccountId' => '5575988449231',
          'displayPhoneNumber' => '+55 75 98844-9231',
          'webhookUrl' => get_count == 1 ? nil : 'http://localhost:3000/webhooks/whatsapp/5575988449231'
        }
      elsif method == :put
        expect(options[:body]).to eq(
          enabled: true,
          webhookUrl: 'http://localhost:3000/webhooks/whatsapp/5575988449231'
        )
        { 'enabled' => true }
      else
        raise "Unexpected request #{method} #{path}"
      end
    end

    expect(described_class.new(channel: channel).ensure!).to eq(:repaired)
    expect(get_count).to eq(2)

    config = channel.reload.provider_config
    expect(config['meta_webhook_url']).to eq('http://localhost:3000/webhooks/whatsapp/5575988449231')
    expect(config['communication_ready']).to be(true)
  end

  it 'preserves the binding reference for an adopted existing instance' do
    config = channel.provider_config.to_h.deep_dup
    config['connect_api_binding_mode'] = 'existing'
    config['api_key'] = 'instance-key'
    config['hub_binding_ref'] = 'binding-ref-1'
    channel.update_columns(provider_config: config)

    bound_client = instance_double(ConnectApi::BoundInstanceClient)
    allow(ConnectApi::BoundInstanceClient).to receive(:new).and_return(bound_client)
    allow(bound_client).to receive(:request).with(
      :get,
      '/compat/meta/hub-realtime-instance',
      timeout: 10
    ).and_return(
      'enabled' => true,
      'phoneNumberId' => '5575988449231',
      'displayPhoneNumber' => '5575988449231',
      'webhookUrl' => 'http://localhost:3000/webhooks/whatsapp/5575988449231?hub_binding_ref=binding-ref-1'
    )

    expect(described_class.new(channel: channel).ensure!).to eq(:ok)
  end
end
