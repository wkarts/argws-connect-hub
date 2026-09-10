require 'rails_helper'

describe Channels::Whatsapp::DeleteConnectApiInstanceJob do
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    allow(ConnectApi::Client).to receive(:new).and_return(client)
  end

  it 'deletes the remote instance' do
    expect(client).to receive(:delete_instance).with('hub-abcd1234-caixa-5575988881111').and_return('status' => 'deleted')

    described_class.perform_now('hub-abcd1234-caixa-5575988881111')
  end

  it 'treats an already absent remote instance as successfully deleted' do
    allow(client).to receive(:delete_instance).and_raise(ConnectApi::Error.new('not found', status: 404))

    expect { described_class.perform_now('hub-abcd1234-caixa-5575988881111') }.not_to raise_error
  end
end
