require 'rails_helper'

RSpec.describe Channels::Whatsapp::ConnectApiMediaSyncSchedulerJob do
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'recovery-throttle-instance'
      }
    )
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch)
      .with('HUB_CONNECT_RECOVERY_ENABLED', 'true')
      .and_return('true')
    allow(ENV).to receive(:fetch)
      .with('HUB_CONNECT_RECOVERY_MIN_INTERVAL_SECONDS', 180)
      .and_return('180')
  end

  it 'enqueues recovery only when the per-inbox throttle slot is available' do
    allow(Rails.cache).to receive(:write)
      .with(
        "hub:connect_api:recovery:#{channel.id}",
        kind_of(Integer),
        expires_in: 180.seconds,
        unless_exist: true
      )
      .and_return(true)

    expect(Channels::Whatsapp::ConnectApiMediaSyncJob)
      .to receive(:perform_later)
      .with(channel.id)

    described_class.perform_now
  end

  it 'does not enqueue a second scan inside the configured interval' do
    allow(Rails.cache).to receive(:write).and_return(false)

    expect(Channels::Whatsapp::ConnectApiMediaSyncJob)
      .not_to receive(:perform_later)

    described_class.perform_now
  end

  it 'can disable only the recovery scanner without affecting realtime' do
    allow(ENV).to receive(:fetch)
      .with('HUB_CONNECT_RECOVERY_ENABLED', 'true')
      .and_return('false')

    expect(Channels::Whatsapp::ConnectApiMediaSyncJob)
      .not_to receive(:perform_later)

    described_class.perform_now
  end
end
