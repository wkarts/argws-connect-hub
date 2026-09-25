require 'rails_helper'

RSpec.describe 'Company workspace applications', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/workspace_apps" }
  let(:app) { account.workspace_apps.create!(name: 'Test application', url: 'https://app.example.test/home') }
  let(:login_app) do
    account.workspace_apps.create!(name: 'Test login', url: 'https://app.example.test/home', auth_mode: 'form_post',
                                  login_url: 'https://app.example.test/login', allow_saved_credentials: true, allow_auto_login: true)
  end
  let(:input) { { username: 'test-user', password: 'not-a-real-password', remember: true, auto_login: true } }

  def launch_as(user, values = input, revision: login_app.integration_revision)
    payload = { integration_revision: revision }
    payload[:workspace_credentials] = values unless values.nil?
    post "#{base}/#{login_app.id}/launch", params: payload, headers: user.create_new_auth_token, as: :json
  end

  it 'requires authentication' do
    get base, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns an empty catalog without provisioning applications' do
    get base, headers: headers, as: :json
    expect(response.parsed_body).to eq([])
  end

  it 'lets administrators create, update and remove applications' do
    post base, params: { workspace_app: { name: 'Manual application', url: 'https://app.example.test' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    patch "#{base}/#{id}", params: { workspace_app: { name: 'Updated label' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['name']).to eq('Updated label')
    delete "#{base}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(account.workspace_apps).to be_empty
  end

  it 'forbids agents from editing the catalog' do
    post base, params: { workspace_app: { name: 'Unauthorized', url: 'https://app.example.test' } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.workspace_apps).to be_empty
  end

  it 'does not resolve application IDs from another company' do
    other_app = create(:account).workspace_apps.create!(name: 'Other company', url: 'https://other.example.test')
    get "#{base}/#{other_app.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps inactive applications out of the user catalog but in administrative settings' do
    app.update!(enabled: false)
    get base, headers: headers, as: :json
    expect(response.parsed_body).to eq([])
    get "#{base}/manage", headers: headers, as: :json
    expect(response.parsed_body.map { |entry| entry['id'] }).to include(app.id)
  end

  it 'enforces application permissions on both catalog and direct access' do
    app.update!(access_mode: 'administrators')
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq([])
    get "#{base}/#{app.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts an uploaded icon without changing the image or requiring external fetches' do
    post base, params: { workspace_app: { name: 'Icon app', url: 'https://app.example.test', icon: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'), allowed_user_ids: [''] } }, headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['icon_url']).to be_present
    expect(WorkspaceApp.find(response.parsed_body['id']).allowed_user_ids).to eq([])
  end

  it 'never creates saved credentials without explicit consent' do
    launch_as(admin, input.merge(remember: false))
    expect(response).to have_http_status(:ok)
    expect(WorkspaceAppCredential.count).to eq(0)
  end

  it 'encrypts opt-in credentials and exposes only metadata through GET' do
    launch_as(admin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['password']).to eq(input[:password])
    expect(response.headers['Cache-Control']).to include('no-store')
    record = WorkspaceAppCredential.last
    expect(record.encrypted_credentials).not_to include(input[:password])
    get "#{base}/#{login_app.id}/credential", headers: headers, as: :json
    expect(response.parsed_body).to include('saved' => true, 'auto_login' => true)
    expect(response.body).not_to include(input[:password], 'encrypted_credentials')
    get base, headers: headers, as: :json
    expect(response.body).not_to include(input[:password], input[:username], 'encrypted_credentials')
  end

  it 'does not share credentials between users' do
    launch_as(admin)
    launch_as(agent, nil)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('credentials_required')
    get "#{base}/#{login_app.id}/credential", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['saved']).to be false
  end

  it 'allows the owner to reuse and delete saved credentials' do
    launch_as(admin)
    launch_as(admin, nil)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['password']).to eq(input[:password])
    delete "#{base}/#{login_app.id}/credential", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(WorkspaceAppCredential.count).to eq(0)
  end

  it 'rejects stale configuration before accepting or returning a secret' do
    launch_as(admin)
    old_revision = login_app.integration_revision
    login_app.update!(login_url: 'https://app.example.test/changed')
    launch_as(admin, input, revision: old_revision)
    expect(response).to have_http_status(:conflict)
    expect(response.body).not_to include(input[:password])
    expect(WorkspaceAppCredential.count).to eq(0)
  end

  it 'does not enable automatic login without individual consent' do
    launch_as(admin, input.merge(auto_login: false))
    get "#{base}/#{login_app.id}/credential", headers: headers, as: :json
    expect(response.parsed_body['auto_login']).to be false
  end

  it 'refuses saved credentials when the company disables storage' do
    login_app.update!(allow_saved_credentials: false, allow_auto_login: false)
    launch_as(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(WorkspaceAppCredential.count).to eq(0)
  end

  it 'does not release passwords via a static API access token' do
    launch_as(admin)
    token = admin.access_token
    post "#{base}/#{login_app.id}/launch", params: { integration_revision: login_app.integration_revision }, headers: { api_access_token: token.token }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(input[:password])
  end

  it 'rejects unavailable applications at launch time' do
    login_app.update!(enabled: false)
    launch_as(admin)
    expect(response).to have_http_status(:forbidden)
    expect(WorkspaceAppCredential.count).to eq(0)
  end

  it 'handles malformed credentials without a server error' do
    launch_as(admin, 'not-an-object')
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
