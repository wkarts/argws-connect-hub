module Enterprise::Audit::User
  extend ActiveSupport::Concern

  included do
    audited only: [
      :availability,
      :display_name,
      :email,
      :name
    ], unless: proc { |_u| true }
  end
end
