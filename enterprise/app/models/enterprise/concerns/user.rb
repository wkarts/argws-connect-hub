module Enterprise::Concerns::User
  extend ActiveSupport::Concern

  included do
    before_validation :ensure_installation_pricing_plan_quantity, on: :create
  end

  def ensure_installation_pricing_plan_quantity
    return unless HubPlatform.pricing_plan == 'premium'

    errors.add(:base, 'User limit reached. Please purchase more licenses from super admin') if User.count >= HubPlatform.pricing_plan_quantity
  end
end
