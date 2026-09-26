# frozen_string_literal: true

module HubDiagnostics::JobTrace
  extend ActiveSupport::Concern

  included do
    around_perform :with_hub_diagnostic_trace
  end

  def serialize
    data = super
    context = diagnostic_context_snapshot
    context.present? ? data.merge('hub_diagnostic_context' => context.stringify_keys) : data
  rescue StandardError => error
    # Diagnostic context propagation is best-effort. If ActiveJob itself already
    # serialized the job, preserve that payload. Native serialization failures
    # still propagate normally.
    raise unless defined?(data) && data

    HubDiagnostics::Recorder.error(
      'diagnostics.job_context_serialize_failed',
      error,
      job_class: self.class.name
    )
    data
  end

  def deserialize(job_data)
    super

    @hub_diagnostic_context = begin
      job_data['hub_diagnostic_context'].to_h.slice('trace_id', 'request_id')
    rescue StandardError => error
      HubDiagnostics::Recorder.error(
        'diagnostics.job_context_deserialize_failed',
        error,
        job_class: self.class.name
      )
      {}
    end
  end

  private

  # This callback must never become part of the job's business decision path.
  # Context assignment/restoration is explicitly best-effort and the functional
  # yield is executed exactly once regardless of diagnostic availability.
  def with_hub_diagnostic_trace
    context = (@hub_diagnostic_context || {}).symbolize_keys
    context[:trace_id] ||= safe_trace_id
    previous_context = diagnostic_context_snapshot
    apply_diagnostic_context(context)

    started = monotonic_now
    attributes = {
      job_id: job_id,
      job_class: self.class.name,
      queue: queue_name,
      attempt: executions
    }

    HubDiagnostics::Recorder.emit('job.started', attributes)

    begin
      yield
      HubDiagnostics::Recorder.emit(
        'job.completed',
        attributes.merge(
          duration_ms: elapsed_ms(started)
        )
      )
    rescue StandardError => error
      HubDiagnostics::Recorder.error('job.failed', error, attributes)
      raise
    ensure
      apply_diagnostic_context(previous_context)
    end
  end

  def safe_trace_id
    SecureRandom.uuid
  rescue StandardError
    nil
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rescue StandardError
    nil
  end

  def elapsed_ms(started)
    return unless started

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
  rescue StandardError
    nil
  end

  def diagnostic_context_snapshot
    {
      trace_id: HubDiagnostics::Context.trace_id,
      request_id: HubDiagnostics::Context.request_id
    }.compact
  rescue StandardError
    {}
  end

  def apply_diagnostic_context(context)
    HubDiagnostics::Context.trace_id = context[:trace_id] || context['trace_id']
    HubDiagnostics::Context.request_id = context[:request_id] || context['request_id']
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'diagnostics.job_context_unavailable',
      error,
      job_class: self.class.name
    )
    nil
  end
end
