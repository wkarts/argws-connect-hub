require 'rails_helper'

RSpec.describe 'Workspace destination diagnostics', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:workspace_application) { account.workspace_apps.create!(name: 'Diagnostic fixture', url: 'https://app.example.test/home') }
  let(:path) { "/api/v1/accounts/#{account.id}/workspace_apps/#{workspace_application.id}/diagnose" }
  let(:service) { instance_double(WorkspaceApps::DestinationProbe, call: { code: 'headers_checked', verdict: 'blocked' }) }

  it 'requires an authenticated interactive account member' do
    expect(WorkspaceApps::DestinationProbe).not_to receive(:new)
    post path, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'uses only the registered URL and caches the bounded read-only probe' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    expect(WorkspaceApps::DestinationProbe).to receive(:new).once.with(url: workspace_application.url, hub_origin: anything).and_return(service)
    2.times do
      post path, params: { url: 'https://127.0.0.1', hub_origin: 'https://untrusted.test' }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['verdict']).to eq('blocked')
      expect(response.headers['Cache-Control']).to include('no-store')
    end
  end

  it 'enforces application access before any network access' do
    workspace_application.update!(access_mode: 'administrators')
    expect(WorkspaceApps::DestinationProbe).not_to receive(:new)
    post path, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not resolve apps from a different company' do
    other = create(:account).workspace_apps.create!(name: 'Other', url: 'https://other.example.test')
    expect(WorkspaceApps::DestinationProbe).not_to receive(:new)
    post "/api/v1/accounts/#{account.id}/workspace_apps/#{other.id}/diagnose", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'does not allow unattended API tokens to trigger probes' do
    expect(WorkspaceApps::DestinationProbe).not_to receive(:new)
    post path, headers: { api_access_token: user.access_token.token }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
