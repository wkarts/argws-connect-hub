require 'rails_helper'

RSpec.describe 'Connect API call capabilities', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'connectapi',
      provider_config: {
        'api_key' => 'must-remain-private',
        'instance_name' => 'hub-call-capabilities-test',
        'calls_supported' => true,
        'incoming_call_ring_enabled' => true
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:inbox) { channel.inbox }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  def payload_for(user)
    get "/api/v1/accounts/#{account.id}/inboxes",
        headers: user.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    response.parsed_body.fetch('payload').find { |record| record['id'] == inbox.id }
  end

  it 'exposes call capability flags to an assigned agent without exposing provider config' do
    data = payload_for(agent)

    expect(data).to include(
      'calls_supported' => true,
      'incoming_call_ring_enabled' => true
    )
    expect(data).not_to have_key('provider_config')
  end

  it 'keeps administrator provider config available but never exposes the Connect API key' do
    data = payload_for(admin)

    expect(data.dig('provider_config', 'calls_supported')).to eq(true)
    expect(data.dig('provider_config', 'incoming_call_ring_enabled')).to eq(true)
    expect(data.dig('provider_config', 'api_key')).to be_nil
  end
end
