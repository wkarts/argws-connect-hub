module Whatsapp::Groups
  class AccessChangedJob < ApplicationJob
    queue_as :critical
    self.log_arguments = false

    def perform(account_id, user_id, inbox_id = nil)
      user = User.find_by(id: user_id)
      return unless user
      scope = WhatsappGroup.where(account_id: account_id)
      scope = scope.where(inbox_id: inbox_id) if inbox_id
      scope.distinct.pluck(:inbox_id).each do |id|
        ActionCable.server.broadcast(user.pubsub_token, event: 'whatsapp_group.changed', data: {
          account_id: account_id, inbox_id: id, group_id: nil, invalidated: true, notify: false
        })
      end
    end
  end
end
