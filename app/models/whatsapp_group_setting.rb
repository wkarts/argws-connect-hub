class WhatsappGroupSetting < ApplicationRecord
  belongs_to :inbox
  validates :inbox_id, uniqueness: true
  validates :selection_mode, inclusion: { in: %w[all selected] }
  validates :default_treatment, inclusion: { in: %w[conversation management] }
  validates :default_access_mode, inclusion: { in: %w[inbox selected] }
  validate :validate_default_users

  def self.for(inbox)
    find_or_create_by!(inbox_id: inbox.id)
  rescue ActiveRecord::RecordNotUnique
    find_by!(inbox_id: inbox.id)
  rescue ActiveRecord::RecordInvalid
    # A concurrent first discovery may see the other insert during validation.
    find_by(inbox_id: inbox.id) || raise
  end

  private

  def validate_default_users
    Whatsapp::Groups::Access.validate_user_ids(self, :default_user_ids, inbox)
  end
end
