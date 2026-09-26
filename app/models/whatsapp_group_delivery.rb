class WhatsappGroupDelivery < ApplicationRecord
  belongs_to :whatsapp_group
  belongs_to :message, optional: true
  belongs_to :whatsapp_group_message, optional: true
  validates :source_id, presence: true, uniqueness: { scope: :whatsapp_group_id }
  validates :treatment, inclusion: { in: %w[conversation management] }
end
