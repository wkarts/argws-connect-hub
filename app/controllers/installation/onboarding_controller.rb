class Installation::OnboardingController < ApplicationController
  before_action :ensure_installation_onboarding

  def index; end

  def create
    begin
      AccountBuilder.new(
        account_name: onboarding_params.dig(:user, :company),
        user_full_name: onboarding_params.dig(:user, :name),
        email: onboarding_params.dig(:user, :email),
        user_password: params.dig(:user, :password),
        super_admin: true,
        confirmed: true
      ).perform
    rescue StandardError => e
      redirect_to '/installation/onboarding', flash: { error: e.message } and return
    end

    redirect_to '/'
  end

  private

  def onboarding_params
    params.permit(user: [:name, :company, :email])
  end

  def ensure_installation_onboarding
    redirect_to '/' if User.exists?
  end
end
