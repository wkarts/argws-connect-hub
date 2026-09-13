module TwoFactor
  class SecretCipher
    PURPOSE = 'hub-two-factor-secret-v1'.freeze

    class << self
      def encrypt(value)
        return if value.blank?

        encryptor.encrypt_and_sign(value, purpose: PURPOSE)
      end

      def decrypt(value)
        return if value.blank?

        encryptor.decrypt_and_verify(value, purpose: PURPOSE)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      private

      def encryptor
        @encryptor ||= ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
      end

      def key
        Rails.application.key_generator.generate_key(PURPOSE, 32)
      end
    end
  end
end
