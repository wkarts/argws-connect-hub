require 'rails_helper'
require 'tmpdir'

RSpec.describe HubDiagnostics::Recorder do
  around do |example|
    previous = {
      'HUB_DIAGNOSTICS_DIR' => ENV['HUB_DIAGNOSTICS_DIR'],
      'HUB_DIAGNOSTICS_ENABLED' => ENV['HUB_DIAGNOSTICS_ENABLED'],
      'HUB_DIAGNOSTICS_QUEUE_SIZE' => ENV['HUB_DIAGNOSTICS_QUEUE_SIZE'],
      'HUB_DIAGNOSTICS_CAPTURE_MODE' => ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'],
      'APP_REVISION' => ENV['APP_REVISION']
    }

    described_class.flush!

    Dir.mktmpdir('hub-diagnostics-recorder-spec') do |directory|
      ENV['HUB_DIAGNOSTICS_DIR'] = directory
      ENV['HUB_DIAGNOSTICS_ENABLED'] = 'true'
      ENV['HUB_DIAGNOSTICS_QUEUE_SIZE'] = '64'
      ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = 'all'
      ENV['APP_REVISION'] = 'spec-build-sha'
      HubDiagnostics::CaptureSession.stop!
      example.run
      described_class.flush!
      HubDiagnostics::CaptureSession.stop!
    end
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    described_class.flush!
  end

  it 'persists queued events only when the diagnostic writer consumes them' do
    described_class.emit('spec.async', account_id: 7)

    expect(described_class.flush!).to be(true)

    record = described_class.store.each_record.find { |item| item['event'] == 'spec.async' }
    expect(record).to include(
      'account_id' => 7,
      'build_sha' => 'spec-build-sha',
      'process_id' => Process.pid
    )
    expect(record['boot_id']).to be_present
    expect(record['process_role']).to be_present
  end

  it 'never propagates storage failures to the application flow' do
    allow_any_instance_of(HubDiagnostics::Store).to receive(:append).and_raise(IOError, 'disk unavailable')

    expect { described_class.emit('spec.storage.failure') }.not_to raise_error
    expect { described_class.flush! }.not_to raise_error
  end

  it 'keeps detailed events only during an active session in session mode' do
    ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = 'session'

    described_class.emit('spec.before.capture', account_id: 1)
    described_class.emit('send.failed', level: 'error', account_id: 1)
    expect(described_class.flush!).to be(true)

    session = HubDiagnostics::CaptureSession.start!(actor_id: 7, duration_minutes: 15)
    described_class.emit('spec.during.capture', account_id: 1)
    expect(described_class.flush!).to be(true)

    HubDiagnostics::CaptureSession.stop!
    described_class.emit('spec.after.capture', account_id: 1)
    expect(described_class.flush!).to be(true)

    records = described_class.store.each_record.to_a
    expect(records.map { |row| row['event'] }).not_to include('spec.before.capture', 'spec.after.capture')
    expect(records.map { |row| row['event'] }).to include('send.failed', 'spec.during.capture')

    captured = records.find { |row| row['event'] == 'spec.during.capture' }
    expect(captured['capture_session_id']).to eq(session['id'])
  end

  it 'tags active capture events even when the global mode persists all events' do
    ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = 'all'
    session = HubDiagnostics::CaptureSession.start!(actor_id: 7, duration_minutes: 15)

    described_class.emit('spec.all.mode.capture')
    expect(described_class.flush!).to be(true)

    record = described_class.store.each_record.find { |row| row['event'] == 'spec.all.mode.capture' }
    expect(record['capture_session_id']).to eq(session['id'])
  end


  it 'falls back to session mode when capture mode is invalid' do
    ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = 'invalid'

    expect(described_class.queue_health[:capture_mode]).to eq('session')
  end

end
