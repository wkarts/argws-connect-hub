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
      'duration_ms' => 250.5
    )
    summary.observe(
      'event' => 'status.received',
      'component' => 'connectapi_ingestion',
      'level' => 'info',
      'timestamp' => '2026-09-19T00:00:02Z',
      'source_id' => 'provider-10',
      'status' => 'delivered'
    )
    summary.observe(
      'event' => 'send.finished',
      'component' => 'hub',
      'level' => 'info',
      'timestamp' => '2026-09-19T00:00:03Z',
      'message_id' => 11,
      'source_id' => 'provider-11',
      'status' => 'progress',
      'duration_ms' => 500.0
    )

    data = summary.to_h

    expect(data[:data_first_event_at]).to eq('2026-09-19T00:00:00Z')
    expect(data[:data_last_event_at]).to eq('2026-09-19T00:00:03Z')
    expect(data[:event_counts]['send.finished']).to eq(2)
    expect(data[:message_flow]['status.received']).to eq(1)
    expect(data[:outbound_without_status_callback_count]).to eq(1)
    expect(data[:outbound_without_status_callback].first['source_id']).to eq('provider-11')
    expect(data[:slowest_operations].first['duration_ms']).to eq(500.0)
  end
end
