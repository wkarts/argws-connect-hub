# frozen_string_literal: true

module HubDiagnostics
  class ExportSummary
    FLOW_EVENTS = %w[
      send.started send.http_response send.finished send.failed send.transport_failed
      webhook.received webhook.unrouted webhook.enqueued webhook.rejected
      webhook.processing_started webhook.processing_completed webhook.processing_failed
      webhook.health_ok webhook.health_repaired webhook.health_failed
      message.persisted message.duplicate message.skipped
      status.received status.applied status.deferred status.orphaned status.ignored status.unknown
      media.downloaded media.unavailable
      sync.background_started sync.background_finished sync.background_failed
      sync.text_processed sync.status_processed sync.record_failed sync.skipped
      receipt.watch_started receipt.watch_applied receipt.watch_completed receipt.watch_failed
      reconciliation.requested reconciliation.message_imported reconciliation.status_updated
      reconciliation.skipped reconciliation.record_failed reconciliation.completed reconciliation.failed
    ].freeze
    SLOW_LIMIT = 20
    PENDING_LIMIT = 100

    def initialize
      @event_counts = Hash.new(0)
      @component_counts = Hash.new(0)
      @level_counts = Hash.new(0)
      @http_status_counts = Hash.new(0)
      @job_class_counts = Hash.new(0)
      @flow_counts = Hash.new(0)
      @slowest = []
      @outbound_without_status = {}
      @first_event_at = nil
      @last_event_at = nil
    end

    def observe(record)
      event = record['event'].to_s
      timestamp = record['timestamp'].to_s
      @first_event_at ||= timestamp.presence
      @last_event_at = timestamp.presence || @last_event_at

      @event_counts[event] += 1 if event.present?
      @component_counts[record['component'].to_s] += 1 if record['component'].present?
      @level_counts[record['level'].to_s] += 1 if record['level'].present?
      @http_status_counts[record['http_status'].to_s] += 1 unless record['http_status'].nil?
      @job_class_counts[record['job_class'].to_s] += 1 if record['job_class'].present?
      @flow_counts[event] += 1 if FLOW_EVENTS.include?(event)

      track_delivery(record)
      track_slow(record)
    end

    def to_h
      {
        data_first_event_at: @first_event_at,
        data_last_event_at: @last_event_at,
        event_counts: sorted(@event_counts),
        component_counts: sorted(@component_counts),
        level_counts: sorted(@level_counts),
        http_status_counts: sorted(@http_status_counts),
        job_class_counts: sorted(@job_class_counts),
        message_flow: FLOW_EVENTS.to_h { |event| [event, @flow_counts[event]] },
        outbound_without_status_callback: @outbound_without_status.values.first(PENDING_LIMIT),
        outbound_without_status_callback_count: @outbound_without_status.length,
        slowest_operations: @slowest.sort_by { |item| -item['duration_ms'].to_f }.first(SLOW_LIMIT)
      }
    end

    private

    def track_delivery(record)
      source_id = record['source_id'].to_s
      return if source_id.blank?

      if record['event'] == 'send.finished' && record['status'].to_s == 'progress'
        @outbound_without_status[source_id] = {
          'message_id' => record['message_id'],
          'source_id' => source_id,
          'timestamp' => record['timestamp'],
          'inbox_id' => record['inbox_id'],
          'conversation_id' => record['conversation_id']
        }.compact
      elsif record['event'] == 'status.received'
        @outbound_without_status.delete(source_id)
      end
    end

    def track_slow(record)
      duration = record['duration_ms']
      return unless duration.is_a?(Numeric)

      item = {
        'event' => record['event'],
        'component' => record['component'],
        'duration_ms' => duration,
        'controller' => record['controller'],
        'action' => record['action'],
        'job_class' => record['job_class'],
        'message_id' => record['message_id'],
        'source_id' => record['source_id'],
        'timestamp' => record['timestamp']
      }.compact

      @slowest << item
      @slowest = @slowest.sort_by { |row| -row['duration_ms'].to_f }.first(SLOW_LIMIT * 2) if @slowest.length > SLOW_LIMIT * 4
    end

    def sorted(hash)
      hash.sort_by { |key, value| [-value, key.to_s] }.to_h
    end
  end
end
