module TwoFactorPolicy
  extend ActiveSupport::Concern

  TWO_FACTOR_POLICIES = %w[optional first_login next_login].freeze

  def two_factor_policy
    value = custom_attributes&.fetch('two_factor_policy', nil).to_s
    TWO_FACTOR_POLICIES.include?(value) ? value : 'optional'
  end

  def two_factor_required?
    two_factor_policy != 'optional'
  end
end
