module Whatsapp::Groups
  class BroadcastFilter
    # Executed by the delivery job, not just at enqueue time. Content never
    # reaches an account-wide channel to be filtered afterwards in JavaScript.
    def self.for(members, event, data)
      payload = data.to_h.with_indifferent_access
      claimed_group = payload[:is_group] || payload.dig(:conversation, :is_group) || payload.dig(:notification, :primary_actor, :is_group) || payload.dig(:additional_attributes, :whatsapp_group)
      account = Account.find_by(id: payload[:account_id])
      return claimed_group ? [] : members.map { |token| [token, data] } unless account
      conversation = nil
      notification = payload[:notification].to_h.with_indifferent_access
      if notification[:primary_actor_type] == 'Conversation'
        conversation = account.conversations.find_by(id: notification[:primary_actor_id])
      elsif payload[:conversation_id].present?
        conversation = account.conversations.find_by(display_id: payload[:conversation_id])
      elsif payload[:conversation].is_a?(Hash)
        conversation = account.conversations.find_by(display_id: payload.dig(:conversation, :id))
      elsif event.to_s.start_with?('conversation.') || payload[:is_group]
        conversation = account.conversations.find_by(display_id: payload[:id])
      end
      group = Access.group_for(conversation)
      if !group && event.to_s.start_with?('contact.')
        contact = account.contacts.find_by(id: payload[:id])
        ids = contact ? contact.contact_inboxes.select(:inbox_id) : []
        jid = contact&.additional_attributes.to_h['group_jid']
        group = WhatsappGroup.find_by(account_id: account.id, inbox_id: ids, jid: jid) if jid
      end
      return [] if !group && claimed_group
      return members.map { |token| [token, data] } unless group

      User.where(pubsub_token: members).filter_map do |user|
        next unless group.allowed?(user)
        muted = group.whatsapp_group_preferences.exists?(user: user, muted: true)
        next if muted && event.to_s.start_with?('notification.')
        personal = payload.deep_dup
        personal[:muted] = true if muted
        personal[:conversation][:muted] = true if muted && personal[:conversation].is_a?(Hash)
        [user.pubsub_token, personal]
      end
    end
  end
end
