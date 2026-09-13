require 'rails_helper'

RSpec.describe 'Frontend two-factor session', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, password: 'Password1!', account: account) }
  let(:secret) { TwoFactor::Totp.generate_secret }

  before do
    user.update!(
      two_factor_secret_ciphertext: TwoFactor::SecretCipher.encrypt(secret),
      two_factor_enabled_at: Time.current,
      two_factor_recovery_codes: []
    )
  end

  it 'challenges the browser login before issuing DeviseTokenAuth headers' do
    post '/frontend_auth/sign_in',
         params: { email: user.email, password: 'Password1!' },
         as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body['two_factor_required']).to be(true)
    expect(response.parsed_body['challenge']).to be_present
    expect(response.headers['access-token']).to be_blank
    expect(response.headers['client']).to be_blank
    expect(response.headers['uid']).to be_blank
  end

  it 'issues the normal DeviseTokenAuth headers only after a valid TOTP challenge' do
    post '/frontend_auth/sign_in',
         params: { email: user.email, password: 'Password1!' },
         as: :json

    challenge = response.parsed_body['challenge']
    counter = Time.current.to_i / TwoFactor::Totp::PERIOD
    code = TwoFactor::Totp.code_for(secret: secret, counter: counter)

    post '/frontend_auth/two_factor/verify',
         params: { challenge: challenge, code: code },
         as: :json

    expect(response).to have_http_status(:success)
    expect(response.body).to include(user.email)
    expect(response.headers['access-token']).to be_present
    expect(response.headers['client']).to be_present
    expect(response.headers['uid']).to eq(user.uid)
  end

  it 'keeps the existing REST sign-in contract untouched for API clients' do
    post new_user_session_url,
         params: { email: user.email, password: 'Password1!' },
         as: :json

    expect(response).to have_http_status(:success)
    expect(response.body).to include(user.email)
    expect(response.headers['access-token']).to be_present
    expect(response.headers['client']).to be_present
    expect(response.headers['uid']).to eq(user.uid)
  end
end
