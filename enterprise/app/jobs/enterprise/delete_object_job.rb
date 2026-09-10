module Enterprise::DeleteObjectJob
  def process_post_deletion_tasks(object, user, ip)
    create_audit_entry(object, user, ip)
  end

  def create_audit_entry(object, user, ip)
    return unless object.class.to_s == 'Inbox' && user.present?

    Enterprise::AuditLog.create(
      auditable: object,
      audited_changes: object.attributes,
      action: 'destroy',
      user: user,
      associated: object.account,
      remote_address: ip
    )
  end
end
