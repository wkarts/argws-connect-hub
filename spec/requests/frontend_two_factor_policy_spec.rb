require 'rails_helper'

RSpec.describe 'Frontend mandatory two-factor authentication policy', type: :request do
  let(:password) { 'Password1!' }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator, password: password, password_confirmation: password) }

  before do
    Rails.cache.clear
  end

  after do
    Rails.cache.clear
  end

  def set_policy!(policy)
    account.update!(custom_attributes: account.custom_attributes.merge('two_factor_policy' => policy))
  end

  describe 'next login policy' do
    before do
      set_policy!('next_login')
    end

    it 'does not issue a browser session before mandatory 2FA enrollment is completed' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['two_factor_setup_required']).to be(true)
      expect(response.parsed_body['required_by_accounts']).to include(account.name)
      expect(response.headers['access-token']).to be_blank

      challenge = response.parsed_body.fetch('challenge')

      post '/frontend_auth/two_factor/enroll',
           params: { challenge: challenge },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['secret']).to be_present
      expect(response.parsed_body['provisioning_uri']).to start_with('otpauth://totp/')
      expect(response.headers['access-token']).to be_blank

      secret = response.parsed_body.fetch('secret')
      counter = Time.current.to_i / TwoFactor::Totp::PERIOD
      code = TwoFactor::Totp.code_for(secret: secret, counter: counter)

      post '/frontend_auth/two_factor/enroll/confirm',
           params: { challenge: challenge, code: code },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
      expect(response.parsed_body['recovery_codes']).to be_present
      expect(user.reload.two_factor_enabled?).to be(true)
    end

    it 'rejects an invalid enrollment code without issuing auth headers' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json
      challenge = response.parsed_body.fetch('challenge')

      post '/frontend_auth/two_factor/enroll',
           params: { challenge: challenge },
           as: :json

      post '/frontend_auth/two_factor/enroll/confirm',
           params: { challenge: challenge, code: '000000' },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['access-token']).to be_blank
      expect(user.reload.two_factor_enabled?).to be(false)
    end
  end

  describe 'first login policy' do
    before do
      set_policy!('first_login')
    end

    it 'requires enrollment while the account membership has never become active' do
      expect(user.account_users.find_by(account: account).active_at).to be_nil

      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['two_factor_setup_required']).to be(true)
      expect(response.headers['access-token']).to be_blank
    end

    it 'does not retroactively force an existing active member' do
      user.account_users.find_by(account: account).update!(active_at: 1.day.ago)

      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['two_factor_setup_required']).not_to be(true)
      expect(response.headers['access-token']).to be_present
    end
  end

  describe 'optional policy' do
    it 'keeps the normal browser login flow when the company does not require 2FA' do
      set_policy!('optional')

      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['two_factor_setup_required']).not_to be(true)
      expect(response.headers['access-token']).to be_present
    end
  end

  describe 'disabling company-mandated 2FA' do
    it 'blocks disabling 2FA while an active company policy requires it' do
      set_policy!('next_login')
      secret = TwoFactor::Totp.generate_secret
      user.update!(
        two_factor_secret_ciphertext: TwoFactor::SecretCipher.encrypt(secret),
        two_factor_enabled_at: Time.current,
        two_factor_last_counter: nil,
        two_factor_recovery_codes: []
      )

      delete '/frontend_auth/two_factor/settings',
             params: { current_password: password, code: '000000' },
             headers: user.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to include('obrigatória')
      expect(user.reload.two_factor_enabled?).to be(true)
    end
  end
end
