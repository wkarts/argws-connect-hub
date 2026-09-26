module Whatsapp::Groups
  class Presenter
    def self.group(group, user, administrative: false)
      value = group.slice(
        :id, :inbox_id, :name, :jid, :treatment, :last_activity_at,
        :last_message_preview, :last_sender_name, :last_message_kind
      )
      value[:avatar_url] = group.avatar_url

      if administrative
        value.merge!(group.slice(:selected, :access_mode, :allowed_user_ids, :lock_version, :policy_version))
        value[:pending_events] = group.whatsapp_group_pending_events.count
        value[:impact] = Configuration.preview(group)
      else
        preference = group.whatsapp_group_preferences.find_by(user: user)
        value[:muted] = preference&.muted? == true
        value[:pinned] = preference&.pinned? == true
        value[:pinned_at] = preference&.pinned_at
        value[:can_reply] = group.active? && group.allowed?(user)
        value[:unread_count] = group.whatsapp_group_messages.where(direction: 'incoming', historical: false)
                                  .where('sent_at > ?', preference&.last_read_at || Time.at(0)).count
        value[:has_legacy_history] = group.conversations.exists?
        value[:has_management_history] = group.whatsapp_group_messages.exists?
        value[:conversation_id] = group.conversations.where(inbox_id: user.assigned_inboxes.select(:id))
                                       .order(last_activity_at: :desc, id: :desc)
                                       .pick(:display_id)
      end
      value
    end

    def self.legacy_message(message)
      {
        id: message.id, source_id: message.source_id, direction: message.outgoing? ? 'outgoing' : 'incoming',
        status: message.status, kind: 'text', sender_name: message.sender&.name, content: message.content,
        sent_at: message.created_at, deleted_at: message.content_attributes.to_h['deleted'] ? message.updated_at : nil,
        historical: true, can_revoke: false,
        sender: {
          name: message.sender&.name.to_s.presence || (message.outgoing? ? I18n.t('conversations.you', default: 'Você') : I18n.t('conversations.group_participant', default: 'Participante')),
          avatar_url: message.sender.respond_to?(:avatar_url) ? message.sender.avatar_url : '',
          own: message.outgoing?
        },
        files: message.attachments.filter_map do |attachment|
          next unless attachment.file.attached?
          { id: attachment.id, name: attachment.file.filename.to_s, content_type: attachment.file.content_type,
            size: attachment.file.byte_size, url: attachment.file_url }
        end
      }
    end

    def self.message(message, reader, participant: nil)
      group = message.whatsapp_group
      value = message.slice(
        :id, :source_id, :direction, :status, :kind, :sender_jid, :sender_name,
        :content, :reply_to_source_id, :sent_at, :deleted_at, :external_error, :historical
      )
      value[:user_name] = message.user&.name
      value[:sender] = participant if participant
      value[:can_revoke] = message.outgoing? && message.source_id.present? && message.deleted_at.nil? && group.active? &&
                          (message.user_id == reader.id || group.account.account_users.exists?(user_id: reader.id, role: :administrator))
      value[:can_cancel] = message.outgoing? && message.source_id.nil? && message.deleted_at.nil? &&
                           %w[queued sending uncertain].include?(message.status) &&
                           (message.user_id == reader.id || group.account.account_users.exists?(user_id: reader.id, role: :administrator))
      value[:files] = message.deleted_at ? [] : message.files.map do |file|
        { id: file.id, name: file.filename.to_s, content_type: file.content_type, size: file.byte_size,
          url: "/api/v1/group_files/#{group.account_id}/#{group.id}/management/#{message.id}/#{file.id}/#{ERB::Util.url_encode(file.filename.to_s)}" }
      end
      value
    end
  end
end
