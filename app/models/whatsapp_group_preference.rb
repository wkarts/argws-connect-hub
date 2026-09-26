class WhatsappGroupPreference < ApplicationRecord
  belongs_to :whatsapp_group
  belongs_to :user
  validates :user_id, uniqueness: { scope: :whatsapp_group_id }
  validates :muted, inclusion: { in: [true, false] }
end
