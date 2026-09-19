require 'rails_helper'
require 'json'
require 'stringio'
require 'tmpdir'
require 'zlib'

RSpec.describe 'Super Admin diagnostics download', type: :request do
  let(:super_admin) { create(:super_admin) }

  around do |example|
    previous_dir = ENV['HUB_DIAGNOSTICS_DIR']
    previous_mode = ENV['HUB_DIAGNOSTICS_CAPTURE_MODE']

    Dir.mktmpdir('hub-diagnostics-spec') do |directory|
      ENV['HUB_DIAGNOSTICS_DIR'] = directory
      ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = 'session'
      HubDiagnostics::CaptureSession.stop!
      example.run
      HubDiagnostics::CaptureSession.stop!
    end
  ensure
    previous_dir.nil? ? ENV.delete('HUB_DIAGNOSTICS_DIR') : ENV['HUB_DIAGNOSTICS_DIR'] = previous_dir
    previous_mode.nil? ? ENV.delete('HUB_DIAGNOSTICS_CAPTURE_MODE') : ENV['HUB_DIAGNOSTICS_CAPTURE_MODE'] = previous_mode
  end

  it 'downloads a valid gzip diagnostic package without encoding conversion errors' do
    sign_in(super_admin, scope: :super_admin)

    HubDiagnostics::Recorder.emit(
      'spec.download',
      account_id: 1,
      inbox_id: 3,
      message_id: 2999,
      source_id: '3EB0A28BC6AAF69C82231B'
    )

    get download_super_admin_diagnostics_path, params: {
      since: 1.hour.ago.in_time_zone('America/Bahia').iso8601,
      until: 1.hour.from_now.in_time_zone('America/Bahia').iso8601
    }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/gzip')
    expect(response.headers.fetch('Content-Disposition')).to include('.jsonl.gz')

    reader = Zlib::GzipReader.new(StringIO.new(response.body.b))
    records = reader.read.lines.map { |line| JSON.parse(line) }

    expect(records.first['kind']).to eq('manifest')
    expect(records.any? { |row| row['event'] == 'spec.download' }).to be(true)
    expect(records.last['kind']).to eq('summary')
    expect(records.last['records']).to be >= 1
    expect(records.last['event_counts']['spec.download']).to eq(1)
    expect(records.last['data_first_event_at']).to be_present
    expect(records.last['data_last_event_at']).to be_present
    expect(records.last['message_flow']).to include('send.finished', 'status.received')
    expect(records.last['outbound_without_status_callback_count']).to be_a(Integer)
  ensure
    reader&.close
  end

  it 'starts and stops a bounded diagnostic capture without changing messaging state' do
    sign_in(super_admin, scope: :super_admin)

    post start_capture_super_admin_diagnostics_path, params: { duration_minutes: 30 }

    expect(response).to have_http_status(:redirect)
    session = HubDiagnostics::CaptureSession.current
    expect(session).to include('actor_id' => super_admin.id)
    expect(Time.iso8601(session['expires_at']) - Time.iso8601(session['started_at'])).to be_within(1).of(30.minutes)

    post stop_capture_super_admin_diagnostics_path

    expect(response).to have_http_status(:redirect)
    expect(HubDiagnostics::CaptureSession.current).to be_nil
  end

  it 'rejects an unsupported capture duration' do
    sign_in(super_admin, scope: :super_admin)

    expect do
      post start_capture_super_admin_diagnostics_path, params: { duration_minutes: 10 }
    end.not_to change { HubDiagnostics::CaptureSession.current }

    expect(response).to have_http_status(:redirect)
    expect(HubDiagnostics::CaptureSession.current).to be_nil
  end

end
