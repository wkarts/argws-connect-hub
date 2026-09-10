class Enterprise::Api::V1::AccountsController < Api::BaseController
  before_action :fetch_account
  before_action :check_authorization

  # HUB 1.x is permanently Enterprise and does not use commercial billing.
  # Keep legacy routes harmless for older frontends while explicitly disabling
  # checkout/subscription operations instead of loading Stripe/Billing services.
  def checkout
    head :not_found
  end

  def subscription
    head :not_found
  end

  def limits
    render json: {
      id: @account.id,
      limits: {
        'conversation' => {},
        'non_web_inboxes' => {}
      }
    }, status: :ok
  end

  private

  def fetch_account
    @account = current_user.accounts.find(params[:id])
    @current_account_user = @account.account_users.find_by(user_id: current_user.id)
  end

  def pundit_user
    {
      user: current_user,
      account: @account,
      account_user: @current_account_user
    }
  end
end
