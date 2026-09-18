# frozen_string_literal: true
module HubDiagnostics
  class Recorder
    def self.store
      Store.new(
        directory: ENV.fetch('HUB_DIAGNOSTICS_DIR', Rails.root.join('log/hub_diagnostics').to_s),
        file_bytes: ENV.fetch('HUB_DIAGNOSTICS_FILE_BYTES', Store::DEFAULT_FILE_BYTES),
        file_count: ENV.fetch('HUB_DIAGNOSTICS_FILE_COUNT', 8),
        retention_seconds: ENV.fetch('HUB_DIAGNOSTICS_RETENTION_SECONDS', 259_200)
      )
    end
    def self.emit(event, attributes = {})
      return if ENV['HUB_DIAGNOSTICS_ENABLED'] == 'false'
      store.append({ event: event, component: 'hub', level: 'info',
                     trace_id: Context.trace_id, request_id: Context.request_id }.merge(attributes))
    rescue StandardError => error
      # Never recurse through Rails.logger and never interrupt messaging for telemetry.
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if !@last_failure || now - @last_failure > 60
        @last_failure = now
        $stderr.puts("[HUB diagnostics unavailable] #{error.class}")
      end
      nil
    end
    def self.error(event, error, attributes = {})
      emit(event, attributes.merge(level: 'error', exception_class: error.class.name,
                                  backtrace: Array(error.backtrace).first(12)))
    end
    def self.message_attributes(message)
      { account_id: message.account_id, inbox_id: message.inbox_id,
        conversation_id: message.conversation_id, message_id: message.id,
        source_id: message.source_id, status: message.status }
    end
  end
end
