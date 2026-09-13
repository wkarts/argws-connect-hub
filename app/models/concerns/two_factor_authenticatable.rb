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
