module Whatsapp::Groups
  class Access
    class << self
      def eligible_users(inbox)
        memberships = inbox.account.account_users
        admins = memberships.where(role: AccountUser.roles.fetch('administrator')).select(:user_id)
        members = InboxMember.where(inbox_id: inbox.id).select(:user_id)
        inbox.account.users.where(id: admins).or(inbox.account.users.where(id: members)).distinct
      end

      def validate_user_ids(record, field, inbox)
        ids = record.public_send(field)
        unless ids.is_a?(Array) && ids.size <= 1000 && ids.uniq == ids && ids.all? { |id| id.is_a?(Integer) && id.positive? }
          record.errors.add(field, 'must contain distinct positive user IDs')
          return
        end
        return if ids.empty?

        record.errors.add(field, 'contains users outside this company or inbox') unless inbox && eligible_users(inbox).where(id: ids).count == ids.size
      end

      def allowed?(group, user)
        return false unless user.is_a?(User)
        return false unless eligible_users(group.inbox).where(id: user.id).exists?

        group.access_mode == 'inbox' || (group.access_mode == 'selected' && group.allowed_user_ids.include?(user.id))
      end

      def scope(user, account, active: false)
        return WhatsappGroup.none unless user.is_a?(User)

        membership = account.account_users.find_by(user_id: user.id)
        return WhatsappGroup.none unless membership

        inboxes = InboxPolicy::Scope.new({ user: user, account: account, account_user: membership }, account.inboxes).resolve
        groups = WhatsappGroup.where(account_id: account.id, inbox_id: inboxes.select(:id))
                              .where("access_mode = 'inbox' OR (access_mode = 'selected' AND allowed_user_ids @> ?::jsonb)", [user.id].to_json)
        return groups unless active

        enabled = Channel::Whatsapp.where(account_id: account.id, provider: 'connectapi')
                                   .where("provider_config->>'ignore_group_messages' IN (?)", ActiveModel::Type::Boolean::FALSE_VALUES.map(&:to_s).uniq)
        groups.where(inbox_id: account.inboxes.where(channel_type: 'Channel::Whatsapp', channel_id: enabled.select(:id)).select(:id))
              .where(treatment: %w[conversation management])
              .where("EXISTS (SELECT 1 FROM whatsapp_group_settings s WHERE s.inbox_id = whatsapp_groups.inbox_id AND (s.selection_mode = 'all' OR (s.selection_mode = 'selected' AND whatsapp_groups.selected = TRUE))) OR NOT EXISTS (SELECT 1 FROM whatsapp_group_settings s WHERE s.inbox_id = whatsapp_groups.inbox_id)")
      end

      # Only adds a group-content restriction; all existing conversation scopes
      # (company, inbox, role, assignee, team) remain in effect.
      def filter_conversations(relation, user, account)
        denied = WhatsappGroup.where(account_id: account.id).where.not(id: scope(user, account).select(:id))
        contacts = ContactInbox.joins('INNER JOIN whatsapp_groups wg ON wg.inbox_id = contact_inboxes.inbox_id AND wg.jid = contact_inboxes.source_id')
                               .where('wg.id IN (?)', denied.select(:id)).select(:id)
        relation.where('conversations.contact_inbox_id IS NULL OR conversations.contact_inbox_id NOT IN (?)', contacts)
      end

      def filter_contacts(relation, user, account)
        denied = WhatsappGroup.where(account_id: account.id).where.not(id: scope(user, account).select(:id))
        contacts = ContactInbox.joins('INNER JOIN whatsapp_groups wg ON wg.inbox_id = contact_inboxes.inbox_id AND wg.jid = contact_inboxes.source_id')
                               .where('wg.id IN (?)', denied.select(:id)).select(:contact_id)
        relation.where.not(id: contacts)
      end

      def assert_contact!(contact, user)
        return if filter_contacts(Contact.where(id: contact.id), user, contact.account).exists?
        raise Pundit::NotAuthorizedError
      end

      def group_for(conversation)
        return unless conversation&.whatsapp_group? && conversation.inbox.channel.provider == 'connectapi'

        WhatsappGroup.find_by(inbox_id: conversation.inbox_id, jid: conversation.contact_inbox.source_id)
      end

      def conversation_allowed?(conversation, user)
        group = group_for(conversation)
        !group || allowed?(group, user)
      end

      def assert_conversation!(conversation, user, write: false)
        group = group_for(conversation)
        return unless group
        raise Pundit::NotAuthorizedError, 'Grupo não autorizado.' unless allowed?(group, user)
        return unless write

        raise Pundit::NotAuthorizedError, 'Este grupo não está habilitado para atendimento.' unless group.active? && group.treatment == 'conversation'
      end

      def notification_allowed?(notification)
        conversation = notification.primary_actor
        return true unless conversation.is_a?(Conversation)

        group = group_for(conversation)
        !group || (allowed?(group, notification.user) && !WhatsappGroupPreference.where(whatsapp_group: group, user: notification.user, muted: true).exists?)
      end
    end
  end
end
