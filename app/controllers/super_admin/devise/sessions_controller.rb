# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    redirect_to(super_admin_session_path, flash: { error: @error_message }) && return unless valid_credentials?

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_root_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def valid_credentials?
    email = params.dig(:super_admin, :email).to_s.strip.downcase
    password = params.dig(:super_admin, :password).to_s
    @super_admin = SuperAdmin.find_by(email: email)

    raise StandardError, 'Credenciais inválidas' unless @super_admin&.valid_password?(password)

    true
  rescue StandardError => e
    Rails.logger.warn("Falha de autenticação do administrador: #{e.message}")
    @error_message = 'E-mail ou senha inválidos. Tente novamente.'
    false
  end
end
