require 'rails_helper'

RSpec.describe Channels::Whatsapp::ConnectApiDeleteInstanceJob do
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    allow(ConnectApi::Client).to receive(:new).and_return(client)
  end

  it 'deletes the remote Connect API instance' do
    allow(client).to receive(:delete_instance).with('hub-abcd1234-caixa-5575988881111').and_return({ 'status' => 'deleted' })

    described_class.perform_now('hub-abcd1234-caixa-5575988881111')

    expect(client).to have_received(:delete_instance).with('hub-abcd1234-caixa-5575988881111').once
  end

  it 'treats an already absent remote instance as successfully deleted' do
    allow(client).to receive(:delete_instance)
      .and_raise(ConnectApi::Error.new('not found', status: 404))

    expect do
      described_class.perform_now('hub-abcd1234-caixa-5575988881111')
    end.not_to raise_error
  end

  it 'raises transient remote errors so ActiveJob can retry them' do
    allow(client).to receive(:delete_instance)
      .and_raise(ConnectApi::Error.new('temporarily unavailable', status: 503))

    expect do
      described_class.perform_now('hub-abcd1234-caixa-5575988881111')
    end.to raise_error(ConnectApi::Error)
  end
end
