# frozen_string_literal: true

require 'securerandom'

module HubDiagnostics
  class RequestTrace
    def initialize(app)
      @app = app
    end

    # Diagnostics wraps the request only observationally. Context bookkeeping is
    # best-effort and @app.call is executed exactly once even if diagnostics is
    # unavailable.
    def call(env)
      previous_context = context_snapshot
      apply_context(
        trace_id: SecureRandom.uuid,
        request_id: env['action_dispatch.request_id'].to_s.first(128)
      )

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, response = @app.call(env)
      params = env['action_dispatch.request.path_parameters'].to_h

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
      [status, headers, response]
    rescue StandardError => error
      params = env['action_dispatch.request.path_parameters'].to_h
      Recorder.error(
        'http.failed',
        error,
        component: 'rails',
        method: env['REQUEST_METHOD'].to_s,
        controller: params[:controller].to_s.presence,
        action: params[:action].to_s.presence,
        duration_ms: elapsed_ms(started)
      )
      raise
    ensure
      apply_context(previous_context || {})
    end

    private

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
    rescue StandardError => error
      Recorder.error('diagnostics.request_context_unavailable', error, component: 'rails')
      nil
    end

    def elapsed_ms(started)
      return unless started

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
    end

    def level_for_status(status)
      code = status.to_i
      return 'error' if code >= 500
      return 'warn' if code >= 400

      'info'
    end
  end
end
