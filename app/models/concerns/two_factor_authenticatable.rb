module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  def two_factor_enabled?
    two_factor_enabled_at.present? && two_factor_secret_ciphertext.present?
  end

  def two_factor_secret
    TwoFactor::SecretCipher.decrypt(two_factor_secret_ciphertext)
  end

  def two_factor_pending_secret
    TwoFactor::SecretCipher.decrypt(two_factor_pending_secret_ciphertext)
  end

  def two_factor_policy_accounts
    account_users.includes(:account).filter_map do |membership|
      account = membership.account
      next unless account&.active? && account.two_factor_required?

      account
    end
  end

  def two_factor_enrollment_accounts
    return [] if two_factor_enabled?

    account_users.includes(:account).filter_map do |membership|
      account = membership.account
      next unless account&.active?

      case account.two_factor_policy
      when 'next_login'
        account
      when 'first_login'
        account if membership.active_at.blank?
      end
    end
  end

  def two_factor_enrollment_required?
    !two_factor_enabled? && two_factor_enrollment_accounts.any?
  end

  def two_factor_disable_blocked?
    two_factor_policy_accounts.any?
  end

  def reset_two_factor_authentication!
    with_lock do
      update!(
        two_factor_secret_ciphertext: nil,
        two_factor_pending_secret_ciphertext: nil,
        two_factor_enabled_at: nil,
        two_factor_last_counter: nil,
        two_factor_recovery_codes: []
      )
    end
  end

  def verify_and_consume_two_factor_code(code)
    return false unless two_factor_enabled?

    normalized = code.to_s.gsub(/\s+/, '')
    return TwoFactor::RecoveryCodes.consume!(self, normalized) unless normalized.match?(/\A\d{6}\z/)

    verified = false
    with_lock do
      secret = two_factor_secret
      next if secret.blank?

      counter = TwoFactor::Totp.verify(
        secret: secret,
        code: normalized,
        after_counter: two_factor_last_counter
      )
      next unless counter

      update_column(:two_factor_last_counter, counter)
      verified = true
    end

    verified
  end
end
