require 'digest'

class WhatsappGroup < ApplicationRecord
  include Avatarable
  JID_PATTERN = /\A\d+(?:-\d+)?@g\.us\z/
  CONFIG_FIELDS = %w[selected treatment access_mode allowed_user_ids].freeze
  belongs_to :account
  belongs_to :inbox
  has_many :whatsapp_group_messages, dependent: :destroy
  has_many :whatsapp_group_pending_events, dependent: :destroy
  has_many :whatsapp_group_deliveries, dependent: :destroy
  has_many :whatsapp_group_preferences, dependent: :destroy
  has_many :whatsapp_group_policy_changes, dependent: :destroy

  validates :jid, format: { with: JID_PATTERN }, uniqueness: { scope: :inbox_id }, length: { maximum: 80 }
  validates :name, presence: true, length: { maximum: 256 }
  validates :treatment, inclusion: { in: %w[conversation management] }
  validates :access_mode, inclusion: { in: %w[inbox selected] }
  validates :selected, inclusion: { in: [true, false] }
  validate :validate_scope
  validate :validate_users

  def self.discover!(inbox, jid, name = nil)
    raise ArgumentError, 'Invalid group JID' unless jid.to_s.match?(JID_PATTERN)

    existing = find_by(inbox_id: inbox.id, jid: jid)
    return existing if existing

    HubDiagnostics::ChannelLock.with(inbox.channel_id) do
      discovery_key = Digest::SHA256.digest("hub:group-discovery:#{inbox.id}:#{jid}").unpack1('q>')
      connection = ActiveRecord::Base.connection
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{discovery_key})")
      raise HubDiagnostics::BindingBusy, 'Group discovery pending' unless locked == true || locked == 't'
      begin
        existing = find_by(inbox_id: inbox.id, jid: jid)
        return existing if existing
        settings = WhatsappGroupSetting.for(inbox)
        legacy = inbox.contact_inboxes.where(source_id: jid).exists?
        create!(account: inbox.account, inbox: inbox, jid: jid, name: name.to_s.strip.presence&.first(256) || jid,
                selected: legacy, treatment: legacy ? 'conversation' : settings.default_treatment,
                access_mode: legacy ? 'inbox' : settings.default_access_mode,
                allowed_user_ids: legacy ? [] : settings.default_user_ids)
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{discovery_key})")
      end
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(inbox_id: inbox.id, jid: jid)
  end

  def active?
    settings = WhatsappGroupSetting.for(inbox)
    return false unless %w[all selected].include?(settings.selection_mode) && %w[conversation management].include?(treatment)
    inbox.channel.reload.groups_enabled? && (settings.selection_mode == 'all' || selected?)
  end

  def management?
    treatment == 'management'
  end

  def conversations
    account.conversations.where(inbox_id: inbox_id, contact_inbox_id: ContactInbox.where(inbox_id: inbox_id, source_id: jid).select(:id))
  end

  def allowed?(user)
    Whatsapp::Groups::Access.allowed?(self, user)
  end

  def allowed_users
    users = Whatsapp::Groups::Access.eligible_users(inbox)
    return users if access_mode == 'inbox'
    return users.where(id: allowed_user_ids) if access_mode == 'selected'
    users.none
  end

  private

  def validate_scope
    errors.add(:inbox, 'must belong to this account and use Connect API') unless
      inbox && inbox.account_id == account_id && inbox.whatsapp? && inbox.channel.provider == 'connectapi'
  end

  def validate_users
    Whatsapp::Groups::Access.validate_user_ids(self, :allowed_user_ids, inbox)
  end
end
