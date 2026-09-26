module Whatsapp::Groups
  class Status
    RANK = { 'received' => 0, 'queued' => 0, 'sending' => 0, 'uncertain' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze

    def self.apply!(message, state, timestamp = nil)
      return if message.deleted_at.present?
      message.with_lock do
        return message if message.deleted_at.present?
        if state == 'deleted'
          message.update!(deleted_at: timestamp || Time.current, content: nil)
          message.files.purge_later
        elsif %w[sent delivered read].include?(state) && RANK.fetch(state) > RANK.fetch(message.status, 0)
          message.update!(status: state, external_error: nil)
        elsif state == 'failed' && RANK.fetch(message.status, 0) < 2
          message.update!(status: 'failed', external_error: 'O provedor informou falha na entrega.')
        end
      end
      message
    end

    # Return false only if this is not a known management message. Never
    # return raw content and never create a ticket to record a receipt.
    def self.consume(inbox, status)
      return false unless status.is_a?(Hash) && status[:id].present?
      scope = WhatsappGroupMessage.joins(:whatsapp_group).where(whatsapp_groups: { account_id: inbox.account_id, inbox_id: inbox.id }, source_id: status[:id].to_s)
      jid = status.dig(:connect_api, :remote_jid).presence || status[:recipient_id]
      if jid.present?
        # A receipt addressed to another kind of peer must not be applied to
        # a management message simply because their source IDs match.
        return false unless jid.to_s.match?(WhatsappGroup::JID_PATTERN)
        scope = scope.where(whatsapp_groups: { jid: jid })
      end
      candidates = scope.limit(2).to_a
      return false if candidates.empty?
      ambiguous_legacy = jid.blank? && Message.where(account_id: inbox.account_id, inbox_id: inbox.id,
                                                      source_id: status[:id].to_s).exists?
      if candidates.size != 1 || ambiguous_legacy
        raise HubDiagnostics::SourceMessagePending, 'Ambiguous group receipt identity'
      end

      message = candidates.first
      Lock.with(message.whatsapp_group) { apply!(message, status[:status].to_s) }
      true
    end
  end
end
