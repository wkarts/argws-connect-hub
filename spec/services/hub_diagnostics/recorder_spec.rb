require 'rails_helper'
require 'tmpdir'

RSpec.describe HubDiagnostics::Recorder do
  around do |example|
    previous = {
      'HUB_DIAGNOSTICS_DIR' => ENV['HUB_DIAGNOSTICS_DIR'],
      'HUB_DIAGNOSTICS_ENABLED' => ENV['HUB_DIAGNOSTICS_ENABLED'],
      'HUB_DIAGNOSTICS_QUEUE_SIZE' => ENV['HUB_DIAGNOSTICS_QUEUE_SIZE'],
      'APP_REVISION' => ENV['APP_REVISION']
    }

    described_class.flush!

    Dir.mktmpdir('hub-diagnostics-recorder-spec') do |directory|
      ENV['HUB_DIAGNOSTICS_DIR'] = directory
      ENV['HUB_DIAGNOSTICS_ENABLED'] = 'true'
      ENV['HUB_DIAGNOSTICS_QUEUE_SIZE'] = '64'
      ENV['APP_REVISION'] = 'spec-build-sha'
      example.run
      described_class.flush!
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
end
