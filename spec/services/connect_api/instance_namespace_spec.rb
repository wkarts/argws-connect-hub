require 'rails_helper'

describe ConnectApi::InstanceNamespace do
  before do
    InstallationConfig.unscoped.where(name: described_class::CONFIG_NAME).delete_all
  end

  it 'creates one immutable installation hash and uses the requested instance naming contract' do
    first_hash = described_class.installation_hash
    second_hash = described_class.installation_hash

    expect(first_hash).to match(/\A[a-f0-9]{8}\z/)
    expect(second_hash).to eq(first_hash)

    name = described_class.build(inbox_name: 'Escola Almeida / Matriz', phone_number: '+55 (75) 98888-1111')
    expect(name).to eq("hub-#{first_hash}-escola-almeida-matriz-5575988881111")
    expect(described_class.owned?(name)).to be(true)
    expect(described_class.owned?('outra-instalacao')).to be(false)
  end
end
