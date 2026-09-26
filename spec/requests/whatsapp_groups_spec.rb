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

  it 'issues a narrowly scoped secure media cookie without breaking authenticated inbox requests' do
    https!
    get "#{base}/inboxes/#{channel.inbox.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    cookie = Array(response.headers['Set-Cookie']).join("\n")
    expect(cookie).to include('hub_group_media_session=')
    expect(cookie.downcase).to include('path=/api/v1/group_files', 'httponly', 'secure', 'samesite=strict')
  end

  it 'does not issue the media cookie to an unauthenticated request' do
    get "#{base}/inboxes/#{channel.inbox.id}", as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Set-Cookie'].to_s).not_to include('hub_group_media_session=')
  end

  context 'group access from jobs without an HTTP account context' do
    let!(:group_record) do
      WhatsappGroup.create!(account: account, inbox: channel.inbox, jid: '120363123456789@g.us',
                            name: 'Grupo', treatment: 'conversation', selected: true)
    end

    after { Current.reset }

    it 'uses native inbox membership with no Current.account and leaves the context untouched' do
      create(:inbox_member, inbox: channel.inbox, user: agent)
      Current.reset
      expect(Whatsapp::Groups::Access.scope(agent, account).pluck(:id)).to eq([group_record.id])
      expect(Current.account).to be_nil
      group_record.update!(access_mode: 'selected', allowed_user_ids: [admin.id])
      expect(Whatsapp::Groups::Access.scope(agent, account)).to be_empty
      expect(Whatsapp::Groups::Access.scope(admin, account).pluck(:id)).to eq([group_record.id])
      expect(Current.account).to be_nil
    end

    it 'uses the explicit account instead of an unrelated ambient administrator context' do
      create(:inbox_member, inbox: channel.inbox, user: agent)
      other_account = create(:account)
      other_membership = create(:account_user, account: other_account, user: agent, role: :administrator)
      other_inbox = create(:inbox, account: other_account)
      Current.account = other_account
      Current.account_user = other_membership
      Current.user = agent
      expect(Whatsapp::Groups::Access.scope(agent, account).pluck(:id)).to eq([group_record.id])
      policy = InboxPolicy::Scope.new({ user: agent, account: account, account_user: account.account_users.find_by!(user: agent) }, account.inboxes)
      expect(policy.resolve.pluck(:id)).not_to include(other_inbox.id)
      expect(Current.account).to eq(other_account)
      expect(Current.account_user).to eq(other_membership)
      expect(Current.user).to eq(agent)
    end

    it 'still denies an agent without inbox membership and a user from another account' do
      Current.reset
      expect(Whatsapp::Groups::Access.scope(agent, account)).to be_empty
      stranger = create(:user, account: create(:account), role: :administrator)
      expect(Whatsapp::Groups::Access.scope(stranger, account)).to be_empty
    end
  end
end
