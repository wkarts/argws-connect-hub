require 'rails_helper'

RSpec.describe 'Company workspace applications', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/workspace_apps" }
  # `app` belongs to the Rails/Rack request harness; do not shadow it with a model.
  let(:workspace_app) { account.workspace_apps.create!(name: 'Test application', url: 'https://app.example.test/home') }
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

  it 'keeps the Rails application as the Rack request target' do
    expect(app).to equal(Rails.application)
    expect { app }.not_to change(WorkspaceApp, :count)
  end

  it 'records safe write failure metadata even outside a capture session' do
    allow(HubDiagnostics::Recorder).to receive(:emit)
    post base, params: { workspace_app: { name: 'Private label', url: 'not-https' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(HubDiagnostics::Recorder).to have_received(:emit).with('workspace.write_failed', hash_including(
      level: 'error', account_id: account.id, exception_class: 'ActiveRecord::RecordInvalid', details: ['url']
    ))
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
    workspace_app.update!(enabled: false)
    get base, headers: headers, as: :json
    expect(response.parsed_body).to eq([])
    get "#{base}/manage", headers: headers, as: :json
    expect(response.parsed_body.map { |entry| entry['id'] }).to include(workspace_app.id)
  end

  it 'enforces application permissions on both catalog and direct access' do
    workspace_app.update!(access_mode: 'administrators')
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq([])
    get "#{base}/#{workspace_app.id}", headers: agent.create_new_auth_token, as: :json
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

  # Match the complete settings form, not just a minimal name/URL API call.
  def registration_values
    {
      name: 'Another application', url: 'https://other.example.test/manager/login', icon_name: 'globe',
      enabled: true, position: 0, launch_mode: 'embedded', auth_mode: 'session', login_url: '',
      username_field: 'username', password_field: 'password', allow_saved_credentials: false,
      allow_auto_login: false, access_mode: 'everyone', allowed_user_ids: [], remove_icon: false
    }
  end

  it 'creates another application from the full JSON form without modifying the existing one' do
    existing = workspace_app.attributes
    post base, params: { workspace_app: registration_values }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
    expect(account.workspace_apps.count).to eq(2)
    expect(workspace_app.reload.attributes).to eq(existing)
  end

  it 'creates from the full multipart form with an icon and a selected company user' do
    values = registration_values.transform_values(&:to_s).merge(
      access_mode: 'selected', allowed_user_ids: [admin.id.to_s],
      icon: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    )
    post base, params: { workspace_app: values }, headers: headers
    expect(response).to have_http_status(:created), response.body
    saved = WorkspaceApp.find(response.parsed_body.fetch('id'))
    expect(saved.allowed_user_ids).to eq([admin.id])
    expect(saved.icon).to be_attached
    expect(saved.allow_saved_credentials).to be false
    expect(saved.allow_auto_login).to be false
  end

  it 'creates from the full multipart form with an icon and no selected users' do
    values = registration_values.transform_values(&:to_s).merge(
      allowed_user_ids: [''], icon: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    )
    post base, params: { workspace_app: values }, headers: headers
    expect(response).to have_http_status(:created), response.body
    expect(WorkspaceApp.find(response.parsed_body.fetch('id')).allowed_user_ids).to eq([])
  end
end
