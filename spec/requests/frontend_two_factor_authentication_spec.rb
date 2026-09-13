require 'rails_helper'

RSpec.describe 'Frontend two-factor authentication', type: :request do
  let(:password) { 'Password1!' }
  let(:user) { create(:user, password: password, password_confirmation: password) }
  let(:secret) { TwoFactor::Totp.generate_secret }

  before do
    Rails.cache.clear
  end

  after do
    Rails.cache.clear
  end

  def enable_two_factor!(resource, totp_secret)
    recovery_codes = TwoFactor::RecoveryCodes.generate
    resource.update!(
      two_factor_secret_ciphertext: TwoFactor::SecretCipher.encrypt(totp_secret),
      two_factor_enabled_at: Time.current,
      two_factor_last_counter: nil,
      two_factor_recovery_codes: TwoFactor::RecoveryCodes.digests(recovery_codes)
    )
  end

  describe 'POST /frontend_auth/sign_in' do
    it 'keeps the normal browser login behavior when 2FA is disabled' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
    end

    it 'requires a second factor without issuing auth headers when 2FA is enabled' do
      enable_two_factor!(user, secret)

      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['two_factor_required']).to be(true)
      expect(response.parsed_body['challenge']).to be_present
      expect(response.headers['access-token']).to be_blank
    end

    it 'does not reveal whether 2FA is enabled when the password is invalid' do
      enable_two_factor!(user, secret)

      post '/frontend_auth/sign_in',
           params: { email: user.email, password: 'WrongPassword1!' },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['two_factor_required']).not_to be(true)
      expect(response.headers['access-token']).to be_blank
    end
  end

  describe 'POST /frontend_auth/two_factor/verify' do
    before do
      enable_two_factor!(user, secret)
    end

    it 'issues the normal DeviseTokenAuth headers only after a valid TOTP code' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      challenge = response.parsed_body.fetch('challenge')
      counter = Time.current.to_i / TwoFactor::Totp::PERIOD
      code = TwoFactor::Totp.code_for(secret: secret, counter: counter)

      post '/frontend_auth/two_factor/verify',
           params: { challenge: challenge, code: code },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
      expect(user.reload.two_factor_last_counter).to eq(counter)
    end

    it 'rejects an invalid code without issuing auth headers' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      challenge = response.parsed_body.fetch('challenge')

      post '/frontend_auth/two_factor/verify',
           params: { challenge: challenge, code: '000000' },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['access-token']).to be_blank
    end

    it 'does not allow a successfully consumed login challenge to be reused' do
      post '/frontend_auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      challenge = response.parsed_body.fetch('challenge')
      counter = Time.current.to_i / TwoFactor::Totp::PERIOD
      code = TwoFactor::Totp.code_for(secret: secret, counter: counter)

      post '/frontend_auth/two_factor/verify',
           params: { challenge: challenge, code: code },
           as: :json
      expect(response).to have_http_status(:success)

      post '/frontend_auth/two_factor/verify',
           params: { challenge: challenge, code: code },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('Desafio de autenticação expirado ou inválido.')
    end
  end

  describe 'existing API authentication compatibility' do
    before do
      enable_two_factor!(user, secret)
    end

    it 'leaves the existing /auth/sign_in token endpoint unchanged' do
      post '/auth/sign_in',
           params: { email: user.email, password: password },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
      expect(response.parsed_body['two_factor_required']).not_to be(true)
    end

    it 'keeps REST v1 authenticated with an existing DeviseTokenAuth token' do
      headers = user.create_new_auth_token

      get '/api/v1/profile', headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(user.id)
    end
  end
end
