# frozen_string_literal: true

require 'securerandom'

module ConnectApi
  class InstanceNamespace
    CONFIG_NAME = 'HUB_CONNECT_API_INSTANCE_HASH'
    HASH_LENGTH = 8
    MAX_SLUG_LENGTH = 40

    class << self
      def build(inbox_name:, phone_number:)
        digits = phone_number.to_s.gsub(/\D/, '')
        raise ArgumentError, 'Número do WhatsApp é obrigatório para criar a instância.' if digits.blank?

        "hub-#{installation_hash}-#{slug(inbox_name)}-#{digits}"
      end

      def owned?(instance_name)
        instance_name.to_s.start_with?("hub-#{installation_hash}-")
      end

      def installation_hash
        record = InstallationConfig.find_by(name: CONFIG_NAME)
        value = normalize_hash(record&.value)
        return value if value.present?

        persist_new_hash
      end

      private

      def persist_new_hash
        value = SecureRandom.hex(HASH_LENGTH / 2)
        record = InstallationConfig.find_or_initialize_by(name: CONFIG_NAME)
        current = normalize_hash(record.value)
        return current if current.present?

        record.value = value
        record.locked = true
        record.save!
        value
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def normalize_hash(value)
        normalized = value.to_s.downcase.gsub(/[^a-f0-9]/, '')
        normalized.length == HASH_LENGTH ? normalized : nil
      end

      def slug(value)
        normalized = I18n.transliterate(value.to_s)
                         .downcase
                         .gsub(/[^a-z0-9]+/, '-')
                         .gsub(/\A-+|-+\z/, '')
        normalized = 'whatsapp' if normalized.blank?
        normalized.first(MAX_SLUG_LENGTH).gsub(/-+\z/, '')
      end
    end
  end
end
