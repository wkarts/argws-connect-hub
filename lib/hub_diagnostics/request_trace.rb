# frozen_string_literal: true
require 'securerandom'
module HubDiagnostics
  class RequestTrace
    def initialize(app)
      @app = app
    end
    def call(env)
      Context.set(trace_id: SecureRandom.uuid, request_id: env['action_dispatch.request_id'].to_s.first(128)) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, headers, response = @app.call(env)
        # No path, query, request parameters, Authorization, cookies or bodies are logged.
        Recorder.emit('http.completed', component: 'rails', http_status: status,
                      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2))
        [status, headers, response]
      rescue StandardError => error
        Recorder.error('http.failed', error, component: 'rails')
        raise
      end
    end
  end
end
