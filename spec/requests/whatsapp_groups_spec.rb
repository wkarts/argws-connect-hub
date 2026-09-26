require 'rails_helper'

RSpec.describe 'WhatsApp group inbox configuration', type: :request do
  let!(:channel) { create(:channel_whatsapp, provider: 'connectapi', sync_templates: false, validate_provider_config: false, provider_config: { instance_name: 'group-http', api_key: 'fixture-key' }) }
  let(:account) { channel.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  def group_conversation
    contact = create(:contact, account: account, name: 'Grupo de teste', phone_number: nil)
    contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '120363123456789@g.us')
    create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
  end

  before do
    allow_any_instance_of(Whatsapp::Providers::ConnectApiService).to receive(:validate_provider_config?).and_return(true)
    allow_any_instance_of(Whatsapp::ConnectApiGroupSettingsService).to receive(:sync!).and_return(true)
  end

  it 'exposes the default-off flag and persists the explicit administrator choice without erasing existing configuration' do
    get "#{base}/inboxes/#{channel.inbox.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['whatsapp_groups_enabled']).to be false
    patch "#{base}/inboxes/#{channel.inbox.id}", params: { channel: { provider_config: { ignore_group_messages: false } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['whatsapp_groups_enabled']).to be true
    expect(channel.reload.provider_config).to include('instance_name' => 'group-http', 'ignore_group_messages' => false)
  end

  it 'does not allow an agent to enable groups in inbox configuration' do
    create(:inbox_member, inbox: channel.inbox, user: agent)
    patch "#{base}/inboxes/#{channel.inbox.id}", params: { channel: { provider_config: { ignore_group_messages: false } } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(channel.reload.groups_enabled?).to be false
  end

  it 'returns the fourth counter and group flag through real conversation endpoints' do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => false))
    conversation = group_conversation
    get "#{base}/conversations", params: { assignee_type: 'groups' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'meta', 'group_count')).to eq(1)
    expect(response.parsed_body.dig('data', 'payload').map { |entry| [entry['id'], entry['is_group']] }).to eq([[conversation.display_id, true]])
    get "#{base}/conversations/meta", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('meta', 'group_count')).to eq(0)
  end
end
