# frozen_string_literal: true

require 'securerandom'

module HubDiagnostics
  class RequestTrace
    def initialize(app)
      @app = app
    end

    # Diagnostics is observational only. @app.call is always executed exactly
    # once, and only an exception raised by the application itself may escape
    # this middleware.
    def call(env)
      previous_context = context_snapshot
      apply_context(
        trace_id: safe_trace_id,
        request_id: env['action_dispatch.request_id'].to_s.first(128)
      )

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        status, headers, response = @app.call(env)
      rescue StandardError => error
        record_failure(env, started, error)
        raise
      end

      record_completion(env, started, status)
      [status, headers, response]
    ensure
      apply_context(previous_context || {})
    end

    private

    def record_completion(env, started, status)
      params = path_parameters(env)
      # Deliberately record the route identity, never the raw path, query,
      # headers, cookies or body. This keeps diagnostics useful without
      # leaking phone numbers or credentials embedded in URLs.
      Recorder.emit(
        'http.completed',
        component: 'rails',
        level: level_for_status(status),
        method: env['REQUEST_METHOD'].to_s,
        controller: params[:controller].to_s.presence,
        action: params[:action].to_s.presence,
        http_status: status,
        duration_ms: elapsed_ms(started)
      )
    rescue StandardError
      nil
    end

    def record_failure(env, started, error)
      params = path_parameters(env)
      Recorder.error(
        'http.failed',
        error,
        component: 'rails',
        method: env['REQUEST_METHOD'].to_s,
        controller: params[:controller].to_s.presence,
        action: params[:action].to_s.presence,
        duration_ms: elapsed_ms(started)
      )
    rescue StandardError
      nil
    end

    def path_parameters(env)
      env['action_dispatch.request.path_parameters'].to_h
    rescue StandardError
      {}
    end

    def safe_trace_id
      SecureRandom.uuid
    rescue StandardError
      nil
    end

    def context_snapshot
      {
        trace_id: Context.trace_id,
        request_id: Context.request_id
      }.compact
    rescue StandardError
      {}
    end

    def apply_context(context)
      Context.trace_id = context[:trace_id] || context['trace_id']
      Context.request_id = context[:request_id] || context['request_id']
    rescue StandardError
      nil
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
    rescue StandardError
      nil
    end

    def level_for_status(status)
      code = status.to_i
      return 'error' if code >= 500
      return 'warn' if code >= 400

      'info'
    rescue StandardError
      'info'
    end
  end
end
