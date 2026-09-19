# frozen_string_literal: true

module HubDiagnostics::JobTrace
  extend ActiveSupport::Concern

  included do
    around_perform :with_hub_diagnostic_trace
  end

  def serialize
    data = super
    context = {
      'trace_id' => HubDiagnostics::Context.trace_id,
      'request_id' => HubDiagnostics::Context.request_id
    }.compact
    context.present? ? data.merge('hub_diagnostic_context' => context) : data
  rescue StandardError => error
    # Diagnostic context propagation is best-effort. If it fails after ActiveJob
    # has serialized the job, preserve the original payload and never block enqueue.
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

  def with_hub_diagnostic_trace
    context = (@hub_diagnostic_context || {}).symbolize_keys
    context[:trace_id] ||= SecureRandom.uuid

    HubDiagnostics::Context.set(**context) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
            duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
          )
        )
      rescue StandardError => error
        HubDiagnostics::Recorder.error('job.failed', error, attributes)
        raise
      end
    end
  end
end
