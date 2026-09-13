require 'digest'
require 'securerandom'

module TwoFactor
  class EnrollmentChallenge
    PURPOSE = 'hub-frontend-two-factor-enrollment'.freeze
    EXPIRES_IN = 15.minutes
    CONSUMED_PREFIX = 'hub:two_factor:consumed_enrollment'.freeze
    ATTEMPTS_PREFIX = 'hub:two_factor:enrollment_attempts'.freeze

    class << self
      def issue(user, accounts:)
        verifier.generate(
          {
            user_id: user.id,
            account_ids: accounts.map(&:id),
            nonce: SecureRandom.hex(16)
          },
          expires_in: EXPIRES_IN,
          purpose: PURPOSE
        )
      end

      def verify(token)
        verifier.verified(token.to_s, purpose: PURPOSE)
      end

      def consumed?(payload)
        redis_pool.with { |redis| !redis.get(consumed_key(payload)).nil? }
      end

      def consume!(payload)
        redis_pool.with do |redis|
          !!redis.set(
            consumed_key(payload),
            '1',
            nx: true,
            ex: EXPIRES_IN.to_i
          )
        end
      end

      def increment_attempts!(payload)
        redis_pool.with do |redis|
          key = attempts_key(payload)
          redis.set(key, '0', nx: true, ex: EXPIRES_IN.to_i)
          redis.incr(key)
        end
      end

      def clear_attempts!(payload)
        redis_pool.with { |redis| redis.del(attempts_key(payload)) }
      end

      private

      def consumed_key(payload)
        "#{CONSUMED_PREFIX}:#{nonce_digest(payload)}"
      end

      def attempts_key(payload)
        "#{ATTEMPTS_PREFIX}:#{nonce_digest(payload)}"
      end

      def nonce_digest(payload)
        nonce = payload[:nonce] || payload['nonce']
        Digest::SHA256.hexdigest(nonce.to_s)
      end

      def redis_pool
        $alfred
      end

      def verifier
        Rails.application.message_verifier(:hub_frontend_two_factor_enrollment)
      end
    end
  end
end
