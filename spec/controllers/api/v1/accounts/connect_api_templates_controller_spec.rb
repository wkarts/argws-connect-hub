require 'rails_helper'

RSpec.describe 'Connect API opening templates', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:channel) do
    create(:channel_whatsapp, account: account, provider: 'connectapi', sync_templates: false, validate_provider_config: false,
                             message_templates: [], provider_config: { 'api_key' => 'private-instance-token', 'instance_name' => 'hub-test' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}/connect_api_templates" }
  let(:template) { { 'name' => 'hello', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Real' }] } }

  before { channel.update_columns(message_templates: channel.opening_template_catalog.reconcile([template, template.merge('name' => 'outro')])) }

  it 'requires authentication' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows administrators to read the scoped catalog without leaking credentials' do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data['payload'].pluck('name')).to eq(%w[hello outro])
    expect(data['opening_templates'].pluck('name')).to eq(['hello'])
    expect(response.body).not_to include('private-instance-token')
  end

  it 'forbids administration by agents even when they belong to the inbox' do
    create(:inbox_member, user: agent, inbox: channel.inbox)
    patch url, params: { name: 'outro', language: 'pt_BR', enabled: true }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(channel.reload.opening_template_catalog.available_templates(opening_only: true).pluck('name')).to eq(['hello'])
  end

  it 'persists a boolean choice without changing remote template content' do
    patch url, params: { name: 'hello', language: 'pt_BR', enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['opening_templates']).to eq([])
    expect(channel.reload.message_templates.first.slice(*template.keys)).to eq(template)
  end

  it 'rejects non-boolean toggles instead of coercing them' do
    patch url, params: { name: 'hello', language: 'pt_BR', enabled: 'false' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(channel.reload.message_templates.first['hub_opening_enabled']).to be(true)
  end

  it 'does not create templates through the administration endpoint' do
    patch url, params: { name: 'invented', language: 'pt_BR', enabled: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'cannot read a box from another account' do
    other_channel = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false)
    get "/api/v1/accounts/#{account.id}/inboxes/#{other_channel.inbox.id}/connect_api_templates", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'exposes only enabled and available templates for opening in the normal inbox payload' do
    get "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['opening_templates'].pluck('name')).to eq(['hello'])
    expect(response.parsed_body['message_templates'].pluck('name')).to eq(%w[hello outro])
  end

  it 'imports templates during an explicit box reconciliation' do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config).and_return(nil)
    expect_any_instance_of(Whatsapp::ConnectApiTemplateSyncService).to receive(:sync!).once
    patch "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}",
          params: { channel: { provider_config: { force_reconcile: true } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'reports a failed template reconciliation rather than claiming success' do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config).and_return(nil)
    allow_any_instance_of(Whatsapp::ConnectApiTemplateSyncService).to receive(:sync!).and_raise(Whatsapp::ConnectApiTemplateSyncService::Error, 'Timeout seguro')
    patch "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}",
          params: { channel: { provider_config: { force_reconcile: true } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body['message']).to include('Timeout seguro')
  end

  it 'does not synchronize templates on an unrelated inbox name update' do
    expect_any_instance_of(Whatsapp::ConnectApiTemplateSyncService).not_to receive(:sync!)
    patch "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}", params: { name: 'New label' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end
end
