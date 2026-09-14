require 'rails_helper'

describe ConnectApi::Client do
  subject(:client) do
    described_class.new(
      base_url: 'https://connect.example.test',
      api_key: 'instance-secret'
    )
  end

  describe '#request' do
    it 'maps connection reset to a controlled 503 error' do
      allow(HTTParty).to receive(:public_send).and_raise(Errno::ECONNRESET)

      expect { client.list_calls('hub-call-recovery-test') }
        .to raise_error(ConnectApi::Error) do |error|
          expect(error.status).to eq(503)
          expect(error.message).to include('Connect|API indisponível')
        end
    end
  end
end
