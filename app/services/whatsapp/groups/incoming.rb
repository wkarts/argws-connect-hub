module Whatsapp::Groups
  module Incoming
    private

    def process_messages
      return super if @group_routing || !Router.declared?(@processed_params)
      begin
        @group_routing = true
        Router.new(inbox).dispatch(@processed_params) { super }
      ensure
        @group_routing = false
      end
    end

    # Both ingestion entry points need the same identity boundary. The
    # status-aware entry point otherwise inherits an inbox-only lookup.
    def find_message_by_source_id(source_id)
      value = @processed_params.to_h.with_indifferent_access
      jid = value.dig(:contacts, 0, :group_id).presence ||
            value.dig(:messages, 0, :connect_api, :remote_jid).presence ||
            value.dig(:statuses, 0, :connect_api, :remote_jid).presence ||
            value.dig(:statuses, 0, :recipient_id)
      return super unless jid.to_s.end_with?('@g.us')
      return unless source_id.present? && jid.to_s.match?(WhatsappGroup::JID_PATTERN)

      contact_ids = ContactInbox.where(inbox_id: inbox.id, source_id: jid).select(:id)
      conversations = inbox.conversations.where(contact_inbox_id: contact_ids).select(:id)
      @message = Message.where(account_id: inbox.account_id, inbox_id: inbox.id,
                               source_id: source_id.to_s, conversation_id: conversations).first
    end

    def process_statuses
      return if Status.consume(inbox, @processed_params.dig(:statuses, 0))
      super
    end
  end
end
