require 'erb'
require 'openssl'
require 'securerandom'
require 'uri'

module TwoFactor
  class Totp
    ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.freeze
    DIGITS = 6
    PERIOD = 30
    WINDOW = 1

    class << self
      def generate_secret
        base32_encode(SecureRandom.random_bytes(20))
      end

      def provisioning_uri(secret:, email:, issuer: 'HUB')
        safe_issuer = issuer.to_s.strip.presence || 'HUB'
        label = "#{safe_issuer}:#{email}"
        query = URI.encode_www_form(
          secret: secret,
          issuer: safe_issuer,
          algorithm: 'SHA1',
          digits: DIGITS,
          period: PERIOD
        )
        "otpauth://totp/#{ERB::Util.url_encode(label)}?#{query}"
      end

      def verify(secret:, code:, after_counter: nil, at: Time.current)
        normalized = code.to_s.gsub(/\s+/, '')
        return unless normalized.match?(/\A\d{#{DIGITS}}\z/)

        current_counter = at.to_i / PERIOD
        ((current_counter - WINDOW)..(current_counter + WINDOW)).each do |counter|
          next if after_counter.present? && counter <= after_counter.to_i
          next unless secure_match?(normalized, code_for(secret: secret, counter: counter))

          return counter
        end

        nil
      end

      def code_for(secret:, counter:)
        key = base32_decode(secret)
        digest = OpenSSL::HMAC.digest('SHA1', key, [counter].pack('Q>'))
        offset = digest.getbyte(-1) & 0x0f
        binary = digest.byteslice(offset, 4).unpack1('N') & 0x7fffffff
        format("%0#{DIGITS}d", binary % (10**DIGITS))
      end

      private

      def secure_match?(left, right)
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def base32_encode(bytes)
        bits = bytes.bytes.map { |byte| byte.to_s(2).rjust(8, '0') }.join
        bits << '0' * ((5 - (bits.length % 5)) % 5)
        bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
      end

      def base32_decode(value)
        bits = value.to_s.upcase.delete('=').chars.filter_map do |char|
          index = ALPHABET.index(char)
          index&.to_s(2)&.rjust(5, '0')
        end.join
        bits.scan(/.{8}/).map { |chunk| chunk.to_i(2) }.pack('C*')
      end
    end
  end
end
