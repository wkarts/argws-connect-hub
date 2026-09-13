require 'rails_helper'

RSpec.describe 'Account two-factor authentication policy', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'allows an administrator to configure the company 2FA policy' do
    put "/api/v1/accounts/#{account.id}",
        params: { two_factor_policy: 'next_login' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(account.reload.two_factor_policy).to eq('next_login')

    get "/api/v1/accounts/#{account.id}",
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['two_factor_policy']).to eq('next_login')
  end

  it 'rejects an unknown 2FA policy value' do
    put "/api/v1/accounts/#{account.id}",
        params: { two_factor_policy: 'invalid-policy' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:bad_request)
    expect(account.reload.two_factor_policy).to eq('optional')
  end
end
