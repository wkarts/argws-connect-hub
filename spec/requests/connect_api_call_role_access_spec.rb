require 'rails_helper'

RSpec.describe 'Connect API call access by account role', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'connectapi',
      provider_config: {
        'api_key' => 'instance-secret',
        'instance_name' => 'hub-call-role-access-test',
        'connect_api_provider' => 'WHATSAPP-ZAPO',
        'calls_supported' => true,
        'voice_supported' => true
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5575996236940') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:call_service) { instance_double(Whatsapp::ConnectApiCallService) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: admin, inbox: inbox)

    allow(Whatsapp::ConnectApiCallService).to receive(:new).and_return(call_service)
    allow(call_service).to receive(:capabilities).and_return(provider: 'WHATSAPP-ZAPO', calls: true, voice: true, video: false)
    allow(call_service).to receive(:list).and_return(
      [
        {
          'callId' => 'incoming-call-1',
          'direction' => 'incoming',
          'status' => 'ringing',
          'terminal' => false
        }
      ]
    )
    allow(call_service).to receive(:offer).and_return(
      'callId' => 'outgoing-call-1',
      'direction' => 'outgoing',
      'status' => 'ringing'
    )
  end

  def calls_path
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/connect_api_calls"
  end

  it 'allows both assigned agents and administrators to see incoming calls' do
    [agent, admin].each do |user|
      get calls_path, headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('calls').first).to include(
        'callId' => 'incoming-call-1',
        'direction' => 'incoming'
      )
    end
  end

  it 'allows both assigned agents and administrators to place calls' do
    [agent, admin].each do |user|
      post calls_path, headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('callId' => 'outgoing-call-1')
    end
  end
end
