require 'rails_helper'

RSpec.describe 'Connect API main-compatible webhook job' do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988449231',
      provider_config: {
        'instance_name' => 'hub-main-compatible',
        'api_key' => 'instance-token',
        'phone_number_id' => '5575988449231'
      }
    )
  end
  let(:process_service) { instance_double(Whatsapp::IncomingMessageConnectApiStatusAwareService, perform: true) }
  let(:params) do
    {
      object: 'whatsapp_business_account',
      phone_number: channel.phone_number,
      entry: [{
        changes: [{
          value: {
            metadata: {
              phone_number_id: channel.provider_config['phone_number_id'],
              display_phone_number: channel.phone_number.delete('+')
            },
            messages: [{
              id: 'MAIN-FLOW-JOB-1',
              from: '557588449231',
              timestamp: Time.current.to_i.to_s,
              type: 'text',
              text: { body: 'teste' }
            }]
          }
        }]
      }]
    }
  end

  around do |example|
    previous = ENV['HUB_CONNECT_RELIABILITY_ENABLED']
    ENV['HUB_CONNECT_RELIABILITY_ENABLED'] = 'true'
    example.run
  ensure
    ENV['HUB_CONNECT_RELIABILITY_ENABLED'] = previous
  end

  it 'uses the status-aware service from main, never the reliable replacement' do
    allow(HubDiagnostics::Recorder).to receive(:emit)
    allow(HubDiagnostics::Recorder).to receive(:error)
    allow(Whatsapp::IncomingMessageConnectApiStatusAwareService).to receive(:new).and_return(process_service)
    allow(Whatsapp::IncomingMessageConnectApiReliableService).to receive(:new)

    Webhooks::WhatsappEventsJob.perform_now(params)

    expect(Whatsapp::IncomingMessageConnectApiStatusAwareService)
      .to have_received(:new)
      .with(inbox: channel.inbox, params: params)
    expect(Whatsapp::IncomingMessageConnectApiReliableService).not_to have_received(:new)
  end
end
