module FrontendAuth
  class TwoFactorAuthenticationController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user

    def show
      render json: status_payload
    end

    def create
      return render_invalid_password unless valid_current_password?
      return render json: { error: 'A autenticação em duas etapas já está ativa.' }, status: :conflict if @user.two_factor_enabled?

      secret = TwoFactor::Totp.generate_secret
      @user.update!(two_factor_pending_secret_ciphertext: TwoFactor::SecretCipher.encrypt(secret))

      render json: status_payload.merge(
        secret: secret,
        provisioning_uri: TwoFactor::Totp.provisioning_uri(
          secret: secret,
          email: @user.email,
          issuer: ENV.fetch('INSTALLATION_NAME', 'HUB')
        )
      )
    end

    def confirm
      secret = @user.two_factor_pending_secret
      return render json: { error: 'Nenhuma configuração 2FA pendente.' }, status: :unprocessable_entity if secret.blank?

      counter = TwoFactor::Totp.verify(secret: secret, code: params[:code])
      return render_invalid_code unless counter

      recovery_codes = TwoFactor::RecoveryCodes.generate
      @user.with_lock do
        @user.update!(
          two_factor_secret_ciphertext: @user.two_factor_pending_secret_ciphertext,
          two_factor_pending_secret_ciphertext: nil,
          two_factor_enabled_at: Time.current,
          two_factor_last_counter: counter,
          two_factor_recovery_codes: TwoFactor::RecoveryCodes.digests(recovery_codes)
        )
      end

      render json: status_payload.merge(recovery_codes: recovery_codes)
    end

    def recovery_codes
      return render_invalid_password unless valid_current_password?
      return render_not_enabled unless @user.two_factor_enabled?
      return render_invalid_code unless @user.verify_and_consume_two_factor_code(second_factor_code)

      codes = TwoFactor::RecoveryCodes.generate
      @user.update!(two_factor_recovery_codes: TwoFactor::RecoveryCodes.digests(codes))
      render json: status_payload.merge(recovery_codes: codes)
    end

    def destroy
      return render_invalid_password unless valid_current_password?
      return render_not_enabled unless @user.two_factor_enabled?
      return render_invalid_code unless @user.verify_and_consume_two_factor_code(second_factor_code)

      @user.update!(
        two_factor_secret_ciphertext: nil,
        two_factor_pending_secret_ciphertext: nil,
        two_factor_enabled_at: nil,
        two_factor_last_counter: nil,
        two_factor_recovery_codes: []
      )
      render json: status_payload
    end

    private

    def set_user
      @user = current_user
    end

    def valid_current_password?
      params[:current_password].present? && @user.valid_password?(params[:current_password])
    end

    def second_factor_code
      params[:recovery_code].presence || params[:code]
    end

    def status_payload
      {
        enabled: @user.two_factor_enabled?,
        enabled_at: @user.two_factor_enabled_at,
        setup_pending: @user.two_factor_pending_secret_ciphertext.present?,
        recovery_codes_remaining: Array(@user.two_factor_recovery_codes).length
      }
    end

    def render_invalid_password
      render json: { error: 'Senha atual inválida.' }, status: :unauthorized
    end

    def render_invalid_code
      render json: { error: 'Código de autenticação inválido.' }, status: :unauthorized
    end

    def render_not_enabled
      render json: { error: 'A autenticação em duas etapas não está ativa.' }, status: :unprocessable_entity
    end
  end
end
