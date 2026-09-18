# frozen_string_literal: true
class HubDiagnostics::ReplayStatusJob < ApplicationJob
  queue_as :high
  self.log_arguments = false
  def perform(event_id, actor_id)
    event = HubDiagnostics::Recorder.store.find(event_id)
    unless event && %w[status.received status.deferred status.orphaned].include?(event['event']) &&
           %w[sent delivered read failed].include?(event['status'])
      raise ArgumentError, 'A retained, replayable status event is required'
    end
    channel = Channel::Whatsapp.find_by(id: event['channel_id'], provider: 'connectapi')
    return unless channel&.inbox
    binding = channel.provider_config.to_h['hub_binding_id'].presence || channel.provider_config.to_h['instance_name']
    raise ArgumentError, 'Binding changed; status replay blocked' unless binding.to_s == event['binding_id'].to_s
    phone = channel.phone_number.gsub(/D/, '')
    payload = { object: 'whatsapp_business_account', entry: [{ changes: [{ value: {
      metadata: { display_phone_number: phone, phone_number_id: channel.provider_config['phone_number_id'] },
      statuses: [{ id: event['source_id'], status: event['status'], timestamp: event['provider_timestamp'] }]
    } }] }] }
    HubDiagnostics::Recorder.emit('mitigation.status_replay', actor_id: actor_id, channel_id: channel.id,
                                  source_id: event['source_id'], parent_event_id: event_id)
    Webhooks::ConnectApiDiagnosticEventsJob.perform_later(channel.id, payload, binding)
  end
end
