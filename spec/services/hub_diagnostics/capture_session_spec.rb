require 'rails_helper'
require 'tmpdir'

RSpec.describe HubDiagnostics::CaptureSession do
  around do |example|
    previous_dir = ENV['HUB_DIAGNOSTICS_DIR']

    Dir.mktmpdir('hub-diagnostics-capture-spec') do |directory|
      ENV['HUB_DIAGNOSTICS_DIR'] = directory
      described_class.stop!
      example.run
      described_class.stop!
    end
  ensure
    previous_dir.nil? ? ENV.delete('HUB_DIAGNOSTICS_DIR') : ENV['HUB_DIAGNOSTICS_DIR'] = previous_dir
  end

  it 'starts and stops a bounded capture session' do
    session = described_class.start!(actor_id: 9, duration_minutes: 30)

    expect(session['id']).to be_present
    expect(session['actor_id']).to eq(9)
    expect(Time.iso8601(session['expires_at']) - Time.iso8601(session['started_at'])).to be_within(1).of(30.minutes)
    expect(described_class.current).to include('id' => session['id'])
    expect(described_class.active?).to be(true)

    expect(described_class.stop!).to be(true)
    expect(described_class.current).to be_nil
    expect(described_class.active?).to be(false)
  end

  it 'rejects unbounded or unsupported capture durations' do
    expect do
      described_class.start!(actor_id: 9, duration_minutes: 10)
    end.to raise_error(ArgumentError)

    expect do
      described_class.start!(actor_id: 9, duration_minutes: 'invalid')
    end.to raise_error(ArgumentError)
  end

  it 'stores only operational references and never channel credentials' do
    inbox = instance_double(Inbox, id: 44)
    channel = instance_double(
      Channel::Whatsapp,
      id: 33,
      inbox: inbox,
      provider_config: {
        'instance_name' => 'diagnostic-instance',
        'api_key' => 'must-not-be-written'
      }
    )

    session = described_class.start!(
      actor_id: 9,
      duration_minutes: 15,
      channel: channel
    )

    expect(session).to include(
      'channel_id' => 33,
      'inbox_id' => 44,
      'instance_name' => 'diagnostic-instance'
    )
    expect(session.to_json).not_to include('must-not-be-written')
    expect(session).not_to have_key('api_key')
  end
end
