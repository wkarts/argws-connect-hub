require 'rails_helper'

RSpec.describe HubDiagnostics::ExportSummary do
  subject(:summary) { described_class.new }

  it 'aggregates event coverage, message flow and unresolved outbound sends' do
    summary.observe(
      'event' => 'send.finished',
      'component' => 'hub',
      'level' => 'info',
      'timestamp' => '2026-09-19T00:00:00Z',
      'message_id' => 10,
      'source_id' => 'provider-10',
      'status' => 'progress',
      'duration_ms' => 250.5,
      'hub_version' => 'develop-a',
      'build_sha' => 'build-a',
      'boot_id' => 'boot-1',
      'process_role' => 'rails'
    )
    summary.observe(
      'event' => 'status.received',
      'component' => 'connectapi_ingestion',
      'level' => 'info',
      'timestamp' => '2026-09-19T00:00:02Z',
      'source_id' => 'provider-10',
      'status' => 'delivered',
      'hub_version' => 'develop-a',
      'build_sha' => 'build-a',
      'boot_id' => 'boot-2',
      'process_role' => 'sidekiq'
    )
    summary.observe(
      'event' => 'send.finished',
      'component' => 'hub',
      'level' => 'info',
      'timestamp' => '2026-09-19T00:00:03Z',
      'message_id' => 11,
      'source_id' => 'provider-11',
      'status' => 'progress',
      'duration_ms' => 500.0,
      'hub_version' => 'develop-b',
      'build_sha' => 'build-b',
      'boot_id' => 'boot-3',
      'process_role' => 'sidekiq'
    )

    data = summary.to_h

    expect(data[:data_first_event_at]).to eq('2026-09-19T00:00:00Z')
    expect(data[:data_last_event_at]).to eq('2026-09-19T00:00:03Z')
    expect(data[:event_counts]['send.finished']).to eq(2)
    expect(data[:message_flow]['status.received']).to eq(1)
    expect(data[:outbound_without_status_callback_count]).to eq(1)
    expect(data[:outbound_without_status_callback].first['source_id']).to eq('provider-11')
    expect(data[:slowest_operations].first['duration_ms']).to eq(500.0)
    expect(data[:hub_version_counts]).to eq('develop-a' => 2, 'develop-b' => 1)
    expect(data[:build_counts]).to eq('build-a' => 2, 'build-b' => 1)
    expect(data[:process_role_counts]).to eq('sidekiq' => 2, 'rails' => 1)
    expect(data[:boot_counts].keys).to contain_exactly('boot-1', 'boot-2', 'boot-3')
  end
end
