# frozen_string_literal: true
class Webhooks::ConnectApiDiagnosticEventsJob < ApplicationJob
  queue_as :high
  self.log_arguments = false
  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 24
  retry_on HubDiagnostics::SourceMessagePending, wait: 5.seconds, attempts: 24 do |job, _error|
    channel_id, payload, binding_id = job.arguments
    value = payload.with_indifferent_access.dig(:entry, 0, :changes, 0, :value)
    item = value&.dig(:statuses)&.first
    HubDiagnostics::Recorder.emit('status.orphaned', level: 'error', channel_id: channel_id,
                                  source_id: item&.dig(:id), status: item&.dig(:status), binding_id: binding_id)
  end
  def perform(channel_id, payload, binding_id)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return HubDiagnostics::Recorder.emit('webhook.skipped', level: 'warn', channel_id: channel_id,
                                        reason: 'channel_missing') unless channel&.inbox
    operation = channel.provider_config.to_h['hub_binding_operation'].to_h
    raise HubDiagnostics::BindingBusy, 'Binding transition pending' if %w[binding needs_review].include?(operation['state'])
    current_binding = channel.provider_config.to_h['hub_binding_id'].to_s.presence || channel.provider_config.to_h['instance_name'].to_s
    unless current_binding == binding_id.to_s
      return HubDiagnostics::Recorder.emit('webhook.skipped', level: 'warn', channel_id: channel_id,
                                          reason: 'binding_changed', binding_id: binding_id)
    end
    unless channel.account.active? && !channel.reauthorization_required?
      return HubDiagnostics::Recorder.emit('webhook.skipped', level: 'warn', channel_id: channel_id,
                                          reason: 'account_or_channel_inactive')
    end
    Whatsapp::IncomingMessageConnectApiReliableService.new(
      inbox: channel.inbox, params: payload.with_indifferent_access
    ).perform
  end
end
