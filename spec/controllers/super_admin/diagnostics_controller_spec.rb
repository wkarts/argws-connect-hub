require 'rails_helper'
require 'json'
require 'stringio'
require 'tmpdir'
require 'zlib'

RSpec.describe 'Super Admin diagnostics download', type: :request do
  let(:super_admin) { create(:super_admin) }

  around do |example|
    previous_dir = ENV['HUB_DIAGNOSTICS_DIR']

    Dir.mktmpdir('hub-diagnostics-spec') do |directory|
      ENV['HUB_DIAGNOSTICS_DIR'] = directory
      example.run
    end
  ensure
    ENV['HUB_DIAGNOSTICS_DIR'] = previous_dir
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
  ensure
    reader&.close
  end
end
