class WhatsappGroupMessage < ApplicationRecord
  MAX_FILE_BYTES = 25.megabytes
  belongs_to :whatsapp_group
  belongs_to :user, optional: true
  has_many_attached :files
  validates :source_id, uniqueness: { scope: :whatsapp_group_id }, allow_nil: true
  validates :client_id, uniqueness: { scope: :whatsapp_group_id }, allow_nil: true
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :status, inclusion: { in: %w[received queued sending sent delivered read failed uncertain] }
  validates :kind, inclusion: { in: %w[text image audio video document sticker location contacts unsupported] }
  validates :content, length: { maximum: 65_536 }, allow_nil: true
  validates :policy_version, :sent_at, presence: true
  validate :validate_files
  before_validation :capture_binding, on: :create
  after_commit :publish_change, on: [:create, :update]

  def outgoing?
    direction == 'outgoing'
  end

  private

  def capture_binding
    self.binding_token ||= Whatsapp::Groups::Provider.binding_token(whatsapp_group.inbox) if whatsapp_group
    self.sender_name ||= user&.name
  end

  def validate_files
    errors.add(:files, 'maximum of one file per message') if files.size > 1
    files.each { |file| errors.add(:files, 'must not exceed 25 MB') if file.blob.byte_size > MAX_FILE_BYTES }
  end

  def publish_change
    Whatsapp::Groups::BroadcastJob.perform_later(whatsapp_group_id, id, nil, [], false, previous_changes.key?('id'))
  end
end
