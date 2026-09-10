module Enterprise::Channelable
  extend ActiveSupport::Concern

  included do
    prepend InstanceMethods
  end

  module InstanceMethods
    def create_audit_log_entry
      account = self.account
      associated_type = 'Account'

      return if inbox.nil?

      auditable_id = inbox.id
      auditable_type = 'Inbox'
      audited_changes = saved_changes.except('updated_at')

      return if audited_changes.blank?
      return if messaging_template_updates?(audited_changes)

      Enterprise::AuditLog.create(
        auditable_id: auditable_id,
        auditable_type: auditable_type,
        action: 'update',
        associated_id: account.id,
        associated_type: associated_type,
        audited_changes: audited_changes
      )
    end

    def messaging_template_updates?(changes)
      return false unless changes.keys.length == 1

      changes.key?('message_templates_last_updated')
    end
  end
end
