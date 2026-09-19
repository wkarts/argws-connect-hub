# frozen_string_literal: true

require 'securerandom'

module HubDiagnostics
  class Recorder
    DEFAULT_QUEUE_SIZE = 2048
    DEFAULT_FLUSH_TIMEOUT = 2.0
    CRITICAL_EVENTS = %w[
      send.failed send.transport_failed send.response_without_id
      template.validation_failed template.send_failed
      webhook.processing_failed webhook.rejected
      job.failed sidekiq.error database.error
    ].freeze

    class << self
      def store
        Store.new(
          directory: ENV.fetch('HUB_DIAGNOSTICS_DIR', Rails.root.join('log/hub_diagnostics').to_s),
          file_bytes: ENV.fetch('HUB_DIAGNOSTICS_FILE_BYTES', Store::DEFAULT_FILE_BYTES),
          file_count: ENV.fetch('HUB_DIAGNOSTICS_FILE_COUNT', 8),
          retention_seconds: ENV.fetch('HUB_DIAGNOSTICS_RETENTION_SECONDS', 259_200)
        )
      end

      # Recording is intentionally asynchronous and best-effort. The request/job
      # path only attempts a non-blocking enqueue; disk I/O and cross-process file
      # locking happen on the diagnostic writer thread.
      def emit(event, attributes = {})
        return if ENV['HUB_DIAGNOSTICS_ENABLED'] == 'false'

        enqueue(
          {
            event: event,
            component: 'hub',
            level: 'info',
            trace_id: Context.trace_id,
            request_id: Context.request_id,
            hub_version: hub_version,
            build_sha: ENV['APP_REVISION'].to_s.first(64).presence,
            boot_id: boot_id,
            process_role: process_role,
            process_id: Process.pid
          }.merge(attributes).compact
        )
      rescue StandardError => error
        report_failure(error)
        nil
      end

      def error(event, error, attributes = {})
        emit(
          event,
          attributes.merge(
            level: 'error',
            exception_class: error.class.name,
            backtrace: Array(error.backtrace).first(12)
          )
        )
      end

      # Admin/export paths may explicitly wait for events already queued by this
      # process. Normal messaging code never calls flush!.
      def flush!(timeout: DEFAULT_FLUSH_TIMEOUT)
        ensure_writer!
        acknowledgement = Queue.new
        @queue.push([nil, acknowledgement])

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        loop do
          begin
            acknowledgement.pop(true)
            return true
          rescue ThreadError
            return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            sleep(0.01)
          end
        end
      rescue StandardError => error
        report_failure(error)
        false
      end

      def queue_health
        session = HubDiagnostics::CaptureSession.current
        {
          queued: @queue&.length.to_i,
          capacity: queue_size,
          writer_alive: @writer_pid == Process.pid && @writer&.alive? == true,
          dropped: @dropped_events.to_i,
          capture_mode: capture_mode,
          capture_session_id: session&.dig('id')
        }.compact
      rescue StandardError
        {
          queued: @queue&.length.to_i,
          capacity: queue_size,
          writer_alive: @writer_pid == Process.pid && @writer&.alive? == true,
          dropped: @dropped_events.to_i,
          capture_mode: capture_mode
        }
      end

      def message_attributes(message)
        {
          account_id: safe_attribute(message, :account_id),
          inbox_id: safe_attribute(message, :inbox_id),
          conversation_id: safe_attribute(message, :conversation_id),
          message_id: safe_attribute(message, :id),
          source_id: safe_attribute(message, :source_id),
          status: safe_attribute(message, :status)
        }.compact
      end

      private

      def enqueue(record)
        ensure_writer!
        @queue.push([record, nil], true)
        record
      rescue ThreadError
        @dropped_events = @dropped_events.to_i + 1
        report_drop
        nil
      end

      def ensure_writer!
        return if @writer_pid == Process.pid && @writer&.alive?

        writer_mutex.synchronize do
          return if @writer_pid == Process.pid && @writer&.alive?

          @queue = SizedQueue.new(queue_size)
          @writer_pid = Process.pid
          @writer = Thread.new(@queue) do |queue|
            Thread.current.name = 'hub-diagnostics-writer' if Thread.current.respond_to?(:name=)
            Thread.current.report_on_exception = false if Thread.current.respond_to?(:report_on_exception=)
            writer_loop(queue)
          end
          @writer.abort_on_exception = false
        end
      end

      def writer_loop(queue)
        loop do
          record, acknowledgement = queue.pop
          begin
            persisted_record = record && record_for_persistence(record)
            store.append(persisted_record) if persisted_record
          rescue StandardError => error
            report_failure(error)
          ensure
            acknowledgement << true if acknowledgement
          end
        end
      end

      def record_for_persistence(record)
        mode = capture_mode
        return record if mode == 'all'
        return critical_event?(record) ? record : nil if mode == 'errors'

        session = HubDiagnostics::CaptureSession.current
        return record.merge(capture_session_id: session['id']) if session
        return record if critical_event?(record)

        nil
      end

      def critical_event?(record)
        record[:level].to_s == 'error' || CRITICAL_EVENTS.include?(record[:event].to_s)
      end

      def capture_mode
        mode = ENV.fetch('HUB_DIAGNOSTICS_CAPTURE_MODE', 'all').to_s.strip.downcase
        %w[all session errors].include?(mode) ? mode : 'all'
      end

      def queue_size
        value = Integer(ENV.fetch('HUB_DIAGNOSTICS_QUEUE_SIZE', DEFAULT_QUEUE_SIZE))
        [[value, 64].max, 65_536].min
      rescue ArgumentError, TypeError
        DEFAULT_QUEUE_SIZE
      end

      def writer_mutex
        @writer_mutex ||= Mutex.new
      end

      def boot_id
        @boot_pid ||= Process.pid
        if @boot_pid != Process.pid
          @boot_pid = Process.pid
          @boot_id = nil
        end
        @boot_id ||= SecureRandom.uuid
      end

      def hub_version
        defined?(Hub) && Hub.respond_to?(:version) ? Hub.version.to_s.presence : nil
      rescue StandardError
        nil
      end

      def process_role
        configured = ENV['HUB_PROCESS_ROLE'].to_s.strip
        return configured.first(64) if configured.present?
        return 'sidekiq' if defined?(Sidekiq) && Sidekiq.respond_to?(:server?) && Sidekiq.server?

        'rails'
      rescue StandardError
        'rails'
      end

      def safe_attribute(record, attribute)
        return unless record.respond_to?(attribute)

        record.public_send(attribute)
      rescue StandardError
        nil
      end

      def report_failure(error)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last_failure && now - @last_failure <= 60

        @last_failure = now
        $stderr.puts("[HUB diagnostics unavailable] #{error.class}")
      rescue StandardError
        nil
      end

      def report_drop
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last_drop_warning && now - @last_drop_warning <= 60

        @last_drop_warning = now
        $stderr.puts('[HUB diagnostics saturated] event dropped without blocking application flow')
      rescue StandardError
        nil
      end
    end
  end
end
