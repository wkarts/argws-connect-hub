require 'rails_helper'

RSpec.describe Internal::CheckNewVersionsJob do
  subject(:job) { described_class.perform_now }

  it 'does not contact an external version or telemetry service' do
    allow(RestClient).to receive(:post)
    allow(RestClient).to receive(:get)

    expect { job }.not_to raise_error
    expect(RestClient).not_to have_received(:post)
    expect(RestClient).not_to have_received(:get)
  end
end
