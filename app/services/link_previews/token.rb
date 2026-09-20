# frozen_string_literal: true

module LinkPreviews
  class Token
    PURPOSE = 'hub-link-preview'
    TTL = 30.minutes

    def self.issue(preview)
      verifier.generate(preview, purpose: PURPOSE, expires_in: TTL)
    end

    def self.verify(value)
      return if value.blank?

      verifier.verify(value.to_s, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.verifier
      Rails.application.message_verifier(:hub_link_preview)
    end
    private_class_method :verifier
  end
end
