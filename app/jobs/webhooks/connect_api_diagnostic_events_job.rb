# frozen_string_literal: true

class Webhooks::ConnectApiDiagnosticEventsJob < ApplicationJob
  queue_as :high
  self.log_arguments = false

  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 24
  retry_on HubDiagnostics::SourceMessagePending, wait: 5.seconds, attempts: 24 do |job, _error|
    channel_id, payload, binding_id = job.arguments
    context = Webhooks::ConnectApiDiagnosticEventsJob.diagnostic_context(channel_id, payload, binding_id)
    HubDiagnostics::Recorder.emit('status.orphaned', context.merge(level: 'error'))
  end

  def perform(channel_id, payload, binding_id)
    context = self.class.diagnostic_context(channel_id, payload, binding_id)
    HubDiagnostics::Recorder.emit('webhook.processing_started', context)

    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    unless channel&.inbox
      HubDiagnostics::Recorder.emit('webhook.skipped', context.merge(level: 'warn', reason: 'channel_missing'))
      return
    end

    operation = channel.provider_config.to_h['hub_binding_operation'].to_h
    raise HubDiagnostics::BindingBusy, 'Binding transition pending' if %w[binding needs_review].include?(operation['state'])

    current_binding = channel.provider_config.to_h['hub_binding_id'].to_s.presence ||
      channel.provider_config.to_h['instance_name'].to_s
    unless current_binding == binding_id.to_s
      HubDiagnostics::Recorder.emit('webhook.skipped', context.merge(level: 'warn', reason: 'binding_changed'))
      return
    end

    unless channel.account.active? && !channel.reauthorization_required?
      HubDiagnostics::Recorder.emit(
        'webhook.skipped',
        context.merge(level: 'warn', reason: 'account_or_channel_inactive')
      )
      return
    end

    Whatsapp::IncomingMessageConnectApiReliableService.new(
      inbox: channel.inbox,
      params: payload.with_indifferent_access
    ).perform

    HubDiagnostics::Recorder.emit('webhook.processing_completed', context)
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'webhook.processing_failed',
      error,
      context || { component: 'connectapi_ingestion', channel_id: channel_id }
    )
    raise
  end

  def self.diagnostic_context(channel_id, payload, binding_id)
    value = payload.with_indifferent_access.dig(:entry, 0, :changes, 0, :value).to_h
    message = Array(value[:messages]).first
    status = Array(value[:statuses]).first
    item = message || status || {}

    {
      component: 'connectapi_ingestion',
      channel_id: channel_id,
      source_id: item[:id].to_s.presence,
      status: status&.dig(:status).to_s.presence,
      payload_kind: message ? 'messages' : (status ? 'statuses' : 'other'),
      binding_id: binding_id
    }.compact
  end
end
