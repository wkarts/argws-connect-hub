# frozen_string_literal: true
class HubDiagnostics::SecretBox
  PURPOSE = 'hub-existing-instance-binding-v1'
  def self.encrypt(value)
    encryptor.encrypt_and_sign(value, expires_in: 24.hours, purpose: PURPOSE)
  end
  def self.decrypt(value)
    encryptor.decrypt_and_verify(value, purpose: PURPOSE) || raise(ArgumentError, 'Expired binding request')
  end
  def self.encryptor
    key = Rails.application.key_generator.generate_key(PURPOSE, 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
  end
end
