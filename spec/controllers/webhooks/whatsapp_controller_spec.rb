require 'rails_helper'

RSpec.describe 'Webhooks::WhatsappController', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  describe 'GET /webhooks/verify' do
    it 'returns 401 when valid params are not present' do
      get "/webhooks/whatsapp/#{channel.phone_number}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 when invalid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns challenge when valid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => channel.provider_config['webhook_verify_token'] }
      expect(response.body).to include '123456'
    end
  end

  describe 'POST /webhooks/whatsapp/{:phone_number}' do
    it 'call the whatsapp events job with the params' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      post '/webhooks/whatsapp/123221321', params: { content: 'hello' }
      expect(response).to have_http_status(:success)
    end


    context 'when Connect|API realtime reliability diagnostics are enabled' do
      let!(:connect_channel) do
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

      around do |example|
        previous = ENV['HUB_CONNECT_RELIABILITY_ENABLED']
        ENV['HUB_CONNECT_RELIABILITY_ENABLED'] = 'true'
        example.run
      ensure
        ENV['HUB_CONNECT_RELIABILITY_ENABLED'] = previous
      end

      it 'keeps the same message webhook job used by main' do
        allow(HubDiagnostics::Recorder).to receive(:emit)
        allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
        allow(Webhooks::ConnectApiDiagnosticEventsJob).to receive(:perform_later)

        payload = {
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                metadata: {
                  phone_number_id: '5575988449231',
                  display_phone_number: '5575988449231'
                },
                messages: [{
                  id: 'MAIN-FLOW-1',
                  from: '557588449231',
                  timestamp: Time.current.to_i.to_s,
                  type: 'text',
                  text: { body: 'teste' }
                }]
              }
            }]
          }]
        }

        post '/webhooks/whatsapp/5575988449231', params: payload

        expect(response).to have_http_status(:ok)
        expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later).once
        expect(Webhooks::ConnectApiDiagnosticEventsJob).not_to have_received(:perform_later)
      end

      it 'preserves the existing call webhook path' do
        allow(Webhooks::ConnectApiCallEventsJob).to receive(:perform_later)
        allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

        post '/webhooks/whatsapp/5575988449231',
             params: {
               event: 'call',
               instance: 'hub-main-compatible',
               data: { id: 'call-1', status: 'ringing' }
             },
             headers: { 'X-Connect-Hub-Token' => 'instance-token' }

        expect(response).to have_http_status(:accepted)
        expect(Webhooks::ConnectApiCallEventsJob).to have_received(:perform_later).once
        expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
      end
    end
  end
end
