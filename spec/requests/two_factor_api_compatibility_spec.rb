require 'rails_helper'

RSpec.describe '2FA API compatibility', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:secret) { TwoFactor::Totp.generate_secret }

  before do
    admin.update!(
      two_factor_secret_ciphertext: TwoFactor::SecretCipher.encrypt(secret),
      two_factor_enabled_at: Time.current,
      two_factor_last_counter: nil,
      two_factor_recovery_codes: TwoFactor::RecoveryCodes.digests(
        TwoFactor::RecoveryCodes.generate
      )
    )
  end

  it 'keeps REST v1 working with the persistent user API access token' do
    get "/api/v1/accounts/#{account.id}",
        headers: { 'HTTP_API_ACCESS_TOKEN' => admin.access_token.token },
        as: :json

    expect(response).to have_http_status(:success)
  end

  it 'keeps REST v2 working with the existing DeviseTokenAuth headers' do
    builder = instance_double(V2::Reports::AgentSummaryBuilder, build: [])
    allow(V2::Reports::AgentSummaryBuilder).to receive(:new).and_return(builder)

    get "/api/v2/accounts/#{account.id}/summary_reports/agent",
        params: {
          since: 1.day.ago.to_i.to_s,
          until: Time.current.to_i.to_s,
          business_hours: true
        },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
  end
end
