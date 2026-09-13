require 'openssl'
require 'securerandom'

module TwoFactor
  class RecoveryCodes
    COUNT = 10
    PURPOSE = 'hub-two-factor-recovery-v1'.freeze

    class << self
      def generate
        Array.new(COUNT) do
          SecureRandom.hex(8).upcase.scan(/.{4}/).join('-')
        end
      end

      def digests(codes)
        codes.map { |code| digest(code) }
      end

      def consume!(user, code)
        candidate = digest(code)
        consumed = false

        user.with_lock do
          stored = Array(user.two_factor_recovery_codes)
          index = stored.index { |item| secure_match?(item.to_s, candidate) }
          next unless index

          stored.delete_at(index)
          user.update_column(:two_factor_recovery_codes, stored)
          consumed = true
        end

        consumed
      end

      private

      def digest(code)
        OpenSSL::HMAC.hexdigest('SHA256', key, normalize(code))
      end

      def normalize(code)
        code.to_s.upcase.gsub(/[^A-Z0-9]/, '')
      end

      def key
        Rails.application.key_generator.generate_key(PURPOSE, 32)
      end

      def secure_match?(left, right)
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
