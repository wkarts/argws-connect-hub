module WorkspaceApps
  class CredentialCipher
    SALT = 'hub-workspace-credentials-v1'.freeze

    class << self
      def encrypt(value, purpose:)
        encryptor.encrypt_and_sign(value, purpose: purpose)
      end

      def decrypt(value, purpose:)
        encryptor.decrypt_and_verify(value, purpose: purpose)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError
        nil
      end

      private

      def encryptor
        key = Rails.application.key_generator.generate_key(SALT, 32)
        ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
      end
    end
  end
end
