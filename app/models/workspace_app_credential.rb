class WorkspaceAppCredential < ApplicationRecord
  belongs_to :workspace_app
  belongs_to :account_user

  validates :encrypted_credentials, :integration_revision, presence: true
  validates :account_user_id, uniqueness: { scope: :workspace_app_id }
  validate :membership_belongs_to_application_account

  def credentials=(value)
    self.encrypted_credentials = WorkspaceApps::CredentialCipher.encrypt(value, purpose: cipher_purpose)
    self.integration_revision = workspace_app.integration_revision
  end

  def credentials
    return unless integration_revision == workspace_app.integration_revision

    WorkspaceApps::CredentialCipher.decrypt(encrypted_credentials, purpose: cipher_purpose)
  end

  private

  def cipher_purpose
    "workspace-app:#{workspace_app_id}:membership:#{account_user_id}"
  end

  def membership_belongs_to_application_account
    return if workspace_app && account_user && workspace_app.account_id == account_user.account_id

    errors.add(:account_user, 'must belong to the application company')
  end
end
