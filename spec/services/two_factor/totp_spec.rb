require 'rails_helper'

RSpec.describe TwoFactor::Totp do
  describe '.code_for' do
    it 'matches the RFC 6238 SHA1 test vector truncated to 6 digits' do
      secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
      counter = 59 / described_class::PERIOD

      expect(described_class.code_for(secret: secret, counter: counter)).to eq('287082')
    end
  end

  describe '.verify' do
    let(:secret) { described_class.generate_secret }
    let(:time) { Time.utc(2026, 9, 13, 18, 0, 0) }
    let(:counter) { time.to_i / described_class::PERIOD }
    let(:code) { described_class.code_for(secret: secret, counter: counter) }

    it 'accepts the current RFC 6238 code' do
      expect(described_class.verify(secret: secret, code: code, at: time)).to eq(counter)
    end

    it 'rejects an invalid code' do
      expect(described_class.verify(secret: secret, code: '000000', at: time)).to be_nil
    end

    it 'does not accept the same or an older counter after it was consumed' do
      expect(
        described_class.verify(
          secret: secret,
          code: code,
          after_counter: counter,
          at: time
        )
      ).to be_nil
    end
  end

  describe '.provisioning_uri' do
    it 'builds a standard otpauth URI compatible with authenticator apps' do
      secret = described_class.generate_secret
      uri = described_class.provisioning_uri(
        secret: secret,
        email: 'user@example.com',
        issuer: 'HUB'
      )

      expect(uri).to start_with('otpauth://totp/')
      expect(uri).to include("secret=#{secret}")
      expect(uri).to include('issuer=HUB')
      expect(uri).to include('algorithm=SHA1')
      expect(uri).to include('digits=6')
      expect(uri).to include('period=30')
    end
  end
end
