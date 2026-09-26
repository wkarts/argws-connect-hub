module Whatsapp::Groups
  class BroadcastJob < ApplicationJob
    queue_as :critical
    self.log_arguments = false

    def perform(group_id, message_id = nil, inbox_id = nil, former_user_ids = [], invalidate = nil, new_message = false)
      group = WhatsappGroup.find_by(id: group_id) if group_id
      inbox = group&.inbox || Inbox.find_by(id: inbox_id)
      return unless inbox

      users = group ? group.allowed_users : Access.eligible_users(inbox)
      recipient_ids = users.ids | Array(former_user_ids)
      message = group&.whatsapp_group_messages&.find_by(id: message_id)
      User.where(id: recipient_ids).find_each do |user|
        # Recheck at delivery, not only when the job was queued. Invalidation
        # contains no message, participant, group name or attachment URL.
        allowed = group ? group.allowed?(user) && group.active? : true
        notify = new_message && allowed && message && !message.historical? && !message.outgoing? &&
                 !WhatsappGroupPreference.where(whatsapp_group_id: group.id, user_id: user.id, muted: true).exists?
        ActionCable.server.broadcast(user.pubsub_token, event: 'whatsapp_group.changed', data: {
          account_id: inbox.account_id, inbox_id: inbox.id, group_id: group&.id, message_id: allowed ? message&.id : nil,
          invalidated: (invalidate.nil? ? message_id.nil? : invalidate) || !allowed, notify: !!notify
        })
      end
    end
  end
end
