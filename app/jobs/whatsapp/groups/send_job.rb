module Whatsapp::Groups
  class SendJob < ApplicationJob
    queue_as :high
    self.log_arguments = false
    retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 12

    def perform(message_id)
      message = WhatsappGroupMessage.find_by(id: message_id)
      return unless message
      group = message.whatsapp_group
      Lock.with(group) do
        message.reload
        # A previous process may have died after the provider accepted the
        # message. A durable sending marker MUST NOT be automatically resent.
        if message.status == 'sending'
          uncertain!(message)
          return
        end
        return unless message.status == 'queued' && message.source_id.nil? && message.deleted_at.nil?
        unless group.active? && group.management? && group.policy_version == message.policy_version && group.allowed?(message.user) && message.binding_token == Provider.binding_token(group.inbox)
          message.update!(status: 'failed', external_error: 'Grupo desabilitado, política alterada ou acesso revogado. Nenhuma mensagem enviada.')
          return
        end
        message.update!(status: 'sending') # committed before HTTP, outside a DB transaction
        begin
          source_id = Provider.new(group.inbox).send!(message)
          message.transaction do
            message.update!(source_id: source_id, status: 'sent', external_error: nil)
            group.whatsapp_group_deliveries.create!(source_id: source_id, treatment: 'management', policy_version: message.policy_version,
                                                   whatsapp_group_message: message)
          end
        rescue StandardError => error
          # Never automatically duplicate a remote side effect, including DB
          # failure after a successful HTTP response. Operator can reconcile it.
          uncertain!(message)
          HubDiagnostics::Recorder.emit('group.send_uncertain', component: 'whatsapp_groups', group_id: group.id,
                                        group_message_id: message.id, exception_class: error.class.name)
        end
      end
    end

    private

    def uncertain!(message)
      message.update!(status: 'uncertain', external_error: 'Envio sem confirmação. Confira o WhatsApp antes de reenviar.')
    end
  end
end
