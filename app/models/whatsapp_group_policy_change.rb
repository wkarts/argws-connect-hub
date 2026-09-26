class WhatsappGroupPolicyChange < ApplicationRecord
  belongs_to :whatsapp_group
  belongs_to :user, optional: true
  validates :version, uniqueness: { scope: :whatsapp_group_id }
end
