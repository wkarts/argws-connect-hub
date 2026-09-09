# frozen_string_literal: true

module HubPasswordPolicy
  extend ActiveSupport::Concern

  included do
    validate :hub_password_meets_policy
  end

  private

  def hub_password_meets_policy
    return if password.blank?

    requirements = Rails.configuration.x.hub.password_policy
    checks = {
      uppercase: [password.scan(/[A-Z]/).length, requirements.uppercase],
      lowercase: [password.scan(/[a-z]/).length, requirements.lowercase],
      number: [password.scan(/[0-9]/).length, requirements.number],
      special: [password.scan(/[^A-Za-z0-9\s]/).length, requirements.special]
    }

    checks.each do |type, (actual, required)|
      next if required.to_i <= 0 || actual >= required.to_i

      errors.add(
        :password,
        I18n.t(
          "hub_password_policy.errors.minimum_#{type}",
          count: required,
          default: "must contain at least %{count} #{type} character(s)"
        )
      )
    end
  end
end
