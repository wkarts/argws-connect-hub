class WhatsappGroupPendingEvent < ApplicationRecord
  belongs_to :whatsapp_group
  validates :source_id, :payload, :reason, :occurred_at, presence: true
  validates :source_id, uniqueness: { scope: :whatsapp_group_id }
end
