module FrontendAuth
  class SessionsController < DeviseOverrides::SessionsController
    wrap_parameters format: []

    MAX_CHALLENGE_ATTEMPTS = 6
    MAX_ENROLLMENT_ATTEMPTS = 6

    def create
      return super if params[:sso_auth_token].present?

      resource = User.from_email(params[:email])
      if frontend_password_valid?(resource)
        if resource.two_factor_enabled?
          return render json: {
            two_factor_required: true,
            challenge: TwoFactor::LoginChallenge.issue(resource),
            recovery_code_allowed: Array(resource.two_factor_recovery_codes).any?
          }, status: :accepted
        end

        required_accounts = resource.two_factor_enrollment_accounts
        if required_accounts.any?
          return render json: {
            two_factor_setup_required: true,
            challenge: TwoFactor::EnrollmentChallenge.issue(resource, accounts: required_accounts),
            required_by_accounts: required_accounts.map(&:name)
          }, status: :accepted
        end
      end

      super
    end

    def verify_two_factor
      payload = TwoFactor::LoginChallenge.verify(params[:challenge])
      return render_invalid_challenge unless payload
      return render_invalid_challenge if TwoFactor::LoginChallenge.consumed?(payload)
      return render_too_many_attempts if challenge_attempts_exceeded?(payload)

      @resource = User.find_by(id: payload[:user_id] || payload['user_id'])
      return render_invalid_challenge unless @resource&.active_for_authentication? && @resource.two_factor_enabled?

      code = params[:recovery_code].presence || params[:code]
      return render_invalid_code unless @resource.verify_and_consume_two_factor_code(code)
      return render_invalid_challenge unless TwoFactor::LoginChallenge.consume!(payload)

      TwoFactor::LoginChallenge.clear_attempts!(payload)
      authenticate_resource_after_two_factor
      render_create_success
    end

    def start_two_factor_enrollment
      payload = verified_enrollment_payload
      return render_invalid_enrollment unless payload

      @resource = enrollment_resource(payload)
      return render_invalid_enrollment unless @resource

      required_accounts = @resource.two_factor_enrollment_accounts
      return render_invalid_enrollment if required_accounts.empty?

      secret = @resource.two_factor_pending_secret
      if secret.blank?
        secret = TwoFactor::Totp.generate_secret
        @resource.update!(two_factor_pending_secret_ciphertext: TwoFactor::SecretCipher.encrypt(secret))
      end

      render json: {
        challenge: params[:challenge],
        secret: secret,
        provisioning_uri: TwoFactor::Totp.provisioning_uri(
          secret: secret,
          email: @resource.email,
          issuer: ENV.fetch('INSTALLATION_NAME', 'HUB')
        ),
        required_by_accounts: required_accounts.map(&:name)
      }
    end

    def confirm_two_factor_enrollment
      payload = verified_enrollment_payload
      return render_invalid_enrollment unless payload
      return render_too_many_enrollment_attempts if enrollment_attempts_exceeded?(payload)

      @resource = enrollment_resource(payload)
      return render_invalid_enrollment unless @resource

      required_accounts = @resource.two_factor_enrollment_accounts
      return render_invalid_enrollment if required_accounts.empty?

      secret = @resource.two_factor_pending_secret
      return render_invalid_enrollment if secret.blank?

      counter = TwoFactor::Totp.verify(secret: secret, code: params[:code])
      return render_invalid_code unless counter
      return render_invalid_enrollment unless TwoFactor::EnrollmentChallenge.consume!(payload)

      recovery_codes = TwoFactor::RecoveryCodes.generate
      @resource.with_lock do
        @resource.update!(
          two_factor_secret_ciphertext: @resource.two_factor_pending_secret_ciphertext,
          two_factor_pending_secret_ciphertext: nil,
          two_factor_enabled_at: Time.current,
          two_factor_last_counter: counter,
          two_factor_recovery_codes: TwoFactor::RecoveryCodes.digests(recovery_codes)
        )
      end

      TwoFactor::EnrollmentChallenge.clear_attempts!(payload)
      authenticate_resource_after_two_factor
      render_enrollment_success(recovery_codes)
    end

    private

    def frontend_password_valid?(resource)
      return false unless resource&.active_for_authentication?

      resource.valid_for_authentication? { resource.valid_password?(params[:password]) }
    end

    def authenticate_resource_after_two_factor
      @token = @resource.create_token
      @resource.save!
      sign_in(:user, @resource, store: false, bypass: false)
    end

    def challenge_attempts_exceeded?(payload)
      TwoFactor::LoginChallenge.increment_attempts!(payload) > MAX_CHALLENGE_ATTEMPTS
    end

    def verified_enrollment_payload
      payload = TwoFactor::EnrollmentChallenge.verify(params[:challenge])
      return unless payload
      return if TwoFactor::EnrollmentChallenge.consumed?(payload)

      payload
    end

    def enrollment_resource(payload)
      resource = User.find_by(id: payload[:user_id] || payload['user_id'])
      return unless resource&.active_for_authentication?
      return if resource.two_factor_enabled?

      resource
    end

    def enrollment_attempts_exceeded?(payload)
      TwoFactor::EnrollmentChallenge.increment_attempts!(payload) > MAX_ENROLLMENT_ATTEMPTS
    end

    def render_enrollment_success(recovery_codes)
      payload = JSON.parse(
        render_to_string(
          partial: 'devise/auth',
          formats: [:json],
          locals: { resource: @resource }
        )
      )
      render json: payload.merge(recovery_codes: recovery_codes)
    end

    def render_invalid_challenge
      render json: { error: 'Desafio de autenticação expirado ou inválido.' }, status: :unauthorized
    end

    def render_invalid_enrollment
      render json: { error: 'Configuração obrigatória de 2FA expirada ou inválida. Inicie o login novamente.' }, status: :unauthorized
    end

    def render_invalid_code
      render json: { error: 'Código de autenticação inválido.' }, status: :unauthorized
    end

    def render_too_many_attempts
      render json: { error: 'Muitas tentativas. Inicie o login novamente.' }, status: :too_many_requests
    end

    def render_too_many_enrollment_attempts
      render json: { error: 'Muitas tentativas. Inicie o login novamente para configurar o 2FA.' }, status: :too_many_requests
    end
  end
end
