require 'rails_helper'

describe Channels::Whatsapp::ConnectApiProfilePictureJob do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'hub-test-instance',
        'phone_number_id' => '5575988881111'
      }
    )
  end
  let!(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '557588449231') }
  let(:contact) { contact_inbox.contact }
  let(:client) { instance_double(ConnectApi::Client) }

  before do
    contact.update!(phone_number: '+55 75 8844-9231')
    allow(ConnectApi::Client).to receive(:new).and_return(client)
    allow(Avatar::AvatarFromUrlJob).to receive(:perform_later)
  end

  it 'fetches the profile picture from the native Connect API endpoint and updates the contact metadata' do
    expect(client).to receive(:request).with(
      :post,
      '/chat/fetchProfilePictureUrl/hub-test-instance',
      body: { number: '557588449231' }
    ).and_return(
      'wuid' => '557588449231@s.whatsapp.net',
      'profilePictureUrl' => 'https://cdn.example/profile.jpg'
    )

    described_class.perform_now(contact.id, channel.id, force: true)

    contact.reload
    expect(contact.additional_attributes.dig('connect_api', 'profile_picture')).to eq('https://cdn.example/profile.jpg')
    expect(contact.additional_attributes.dig('connect_api', 'profile_picture_checked_at')).to be_present
    expect(Avatar::AvatarFromUrlJob).to have_received(:perform_later).with(contact, 'https://cdn.example/profile.jpg')
  end
end
