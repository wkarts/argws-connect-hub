require 'rails_helper'

RSpec.describe HubPlatform do
  describe '.installation_identifier' do
    it 'keeps a stable local installation identifier' do
      identifier = described_class.installation_identifier
      expect(identifier).to be_present
      expect(described_class.installation_identifier).to eq(identifier)
    end
  end

  describe 'privacy compatibility facade' do
    it 'does not transmit registration, metrics, events, billing or push payloads' do
      allow(RestClient).to receive(:post)
      allow(RestClient).to receive(:get)

      expect(described_class.sync_with_hub).to be_nil
      expect(described_class.register_instance('company', 'owner', 'owner@example.com')).to be_nil
      expect(described_class.emit_event('event', sample: true)).to be_nil
      expect(described_class.send_push(sample: true)).to be_nil
      expect(described_class.billing_url).to eq('')
      expect(described_class.instance_metrics).to eq({})

      expect(RestClient).not_to have_received(:post)
      expect(RestClient).not_to have_received(:get)
    end
  end
end
