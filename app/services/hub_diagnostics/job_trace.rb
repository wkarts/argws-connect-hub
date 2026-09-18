# frozen_string_literal: true
module HubDiagnostics::JobTrace
  extend ActiveSupport::Concern
  included do
    around_perform :with_hub_diagnostic_trace
  end
  def serialize
    snapshot = @hub_binding_snapshot
    if snapshot.nil? && self.class.name == 'SendReplyJob' && arguments.first
      message = Message.find_by(id: arguments.first)
      channel = message&.conversation&.inbox&.channel
      if channel.is_a?(Channel::Whatsapp) && channel.provider == 'connectapi'
        config = channel.provider_config.to_h
        snapshot = { 'channel_id' => channel.id, 'binding_id' => config['hub_binding_id'].presence || config['instance_name'], 'message_id' => message.id }
      end
    end
    super.merge('hub_binding_snapshot' => snapshot, 'hub_diagnostic_context' => {
      'trace_id' => HubDiagnostics::Context.trace_id,
      'request_id' => HubDiagnostics::Context.request_id
    }.compact)
  end
  def deserialize(job_data)
    super
    @hub_binding_snapshot = job_data['hub_binding_snapshot']
    @hub_diagnostic_context = job_data['hub_diagnostic_context'].to_h.slice('trace_id', 'request_id')
  end
  private
  def with_hub_diagnostic_trace
    context = (@hub_diagnostic_context || {}).symbolize_keys
    context[:trace_id] ||= SecureRandom.uuid
    context[:binding_snapshot] = @hub_binding_snapshot
    HubDiagnostics::Context.set(**context) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      attributes = { job_id: job_id, job_class: self.class.name, queue: queue_name, attempt: executions }
      HubDiagnostics::Recorder.emit('job.started', attributes)
      if @hub_binding_snapshot
        snapshot = @hub_binding_snapshot
        channel = Channel::Whatsapp.find_by(id: snapshot['channel_id'])
        config = channel&.provider_config.to_h
        binding_id = config['hub_binding_id'].presence || config['instance_name']
        if binding_id.to_s != snapshot['binding_id'].to_s
          HubDiagnostics::Recorder.emit('send.stale_job_blocked', attributes.merge(channel_id: snapshot['channel_id'], message_id: snapshot['message_id'], reason: 'binding_changed'))
          return
        end
      end
      begin
        yield
        HubDiagnostics::Recorder.emit('job.completed', attributes.merge(
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        ))
      rescue StandardError => error
        HubDiagnostics::Recorder.error('job.failed', error, attributes)
        raise
      end
    end
  end
end
