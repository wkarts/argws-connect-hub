module FrontendAuth
  class SessionsController < DeviseOverrides::SessionsController
    wrap_parameters format: []

    MAX_CHALLENGE_ATTEMPTS = 6

    def create
      return super if params[:sso_auth_token].present?

      resource = User.from_email(params[:email])
      if frontend_password_valid?(resource) && resource.two_factor_enabled?
        return render json: {
          two_factor_required: true,
          challenge: TwoFactor::LoginChallenge.issue(resource),
          recovery_code_allowed: Array(resource.two_factor_recovery_codes).any?
        }, status: :accepted
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

    def render_invalid_challenge
      render json: { error: 'Desafio de autenticação expirado ou inválido.' }, status: :unauthorized
    end

    def render_invalid_code
      render json: { error: 'Código de autenticação inválido.' }, status: :unauthorized
    end

    def render_too_many_attempts
      render json: { error: 'Muitas tentativas. Inicie o login novamente.' }, status: :too_many_requests
    end
  end
end
