# frozen_string_literal: true
class HubDiagnostics::BindExistingInstanceJob < ApplicationJob
  queue_as :high
  self.log_arguments = false
  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 24
  def perform(binding_ticket, operation_id = nil)
    request = HubDiagnostics::SecretBox.decrypt(binding_ticket)
    channel = Channel::Whatsapp.find(request.fetch('channel_id'))
    service = ConnectApi::ExistingInstanceBinding.new(channel: channel, instance_name: request.fetch('instance_name'),
                                                     api_key: request.fetch('api_key'))
    HubDiagnostics::InstanceLock.with(request.fetch('instance_name')) do
    if request['recover']
      service.recover!(actor_id: request['actor_id'], operation_id: request['operation_id'])
    else
      service.apply!(proof: request.fetch('proof'), actor_id: request['actor_id'], operation_id: request['operation_id'],
                     allow_takeover: request['allow_takeover'] == true)
    end
    end
  rescue ConnectApi::ExistingInstanceBinding::Rejected => error
    HubDiagnostics::Recorder.emit('binding.rejected', level: 'error', operation_id: request&.dig('operation_id') || operation_id,
                                  channel_id: request&.dig('channel_id'), reason: error.message)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError => error
    HubDiagnostics::Recorder.error('binding.request_invalid', error, operation_id: operation_id)
  end
end
