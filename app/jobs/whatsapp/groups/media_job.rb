module Whatsapp::Groups
  class MediaJob < ApplicationJob
    queue_as :low
    self.log_arguments = false
    retry_on ConnectApi::Error, wait: 30.seconds, attempts: 3
    retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 12

    def perform(message_id)
      message = WhatsappGroupMessage.find_by(id: message_id)
      return unless message && message.deleted_at.nil? && !message.files.attached?
      unless message.binding_token == Provider.binding_token(message.whatsapp_group.inbox)
        message.update!(external_error: 'A instância da caixa mudou antes de recuperar esta mídia. Não foi consultada outra instância.')
        return
      end

      Lock.with(message.whatsapp_group) do
        message.reload
        return if message.deleted_at || message.files.attached?
        unless message.binding_token == Provider.binding_token(message.whatsapp_group.inbox)
          message.update!(external_error: 'A instância da caixa mudou antes de recuperar esta mídia. Não foi consultada outra instância.')
          return
        end
        payload = Provider.new(message.whatsapp_group.inbox).fetch_media(message)
        message.with_lock do
          return if message.deleted_at || message.files.attached?
          message.files.attach(payload)
        end
      end
      BroadcastJob.perform_later(message.whatsapp_group_id, message.id)
    end
  end
end
