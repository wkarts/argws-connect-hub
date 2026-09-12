# == Schema Information
#
# Table name: campaigns
#
#  id                                 :bigint           not null, primary key
#  audience                           :jsonb
#  campaign_status                    :integer          default("active"), not null
#  campaign_type                      :integer          default("ongoing"), not null
#  description                        :text
#  enabled                            :boolean          default(TRUE)
#  message                            :text             not null
#  message_attributes                 :jsonb            default({}), not null
#  scheduled_at                       :datetime
#  title                              :string           not null
#  trigger_only_during_business_hours :boolean          default(FALSE)
#  trigger_rules                      :jsonb
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  account_id                         :bigint           not null
#  display_id                         :integer          not null
#  inbox_id                           :bigint           not null
#  sender_id                          :integer
#
# Indexes
#
#  index_campaigns_on_account_id       (account_id)
#  index_campaigns_on_campaign_status  (campaign_status)
#  index_campaigns_on_campaign_type    (campaign_type)
#  index_campaigns_on_inbox_id         (inbox_id)
#  index_campaigns_on_scheduled_at     (scheduled_at)
#
class Campaign < ApplicationRecord
  include UrlHelper

  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :title, presence: true
  validates :message, presence: true
  validate :validate_campaign_inbox
  validate :validate_channel_message_attributes
  validate :validate_outbound_audience
  validate :validate_url
  validate :prevent_completed_campaign_from_update, on: :update

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true

  enum campaign_type: { ongoing: 0, one_off: 1 }
  enum campaign_status: { active: 0, completed: 1 }

  has_many :conversations, dependent: :nullify, autosave: true

  before_validation :ensure_correct_campaign_attributes
  after_commit :set_display_id, unless: :display_id?

  def campaign_type=(value)
    @campaign_type_explicitly_set = true
    super
  end

  def trigger!
    return if completed?

    if one_off?
      Campaigns::OneoffCampaignService.new(campaign: self).perform
    elsif ongoing? && Campaigns::ChannelDriverResolver.supported?(inbox)
      Campaigns::RecurringCampaignService.new(campaign: self).perform
    end
  end

  def channel_capabilities
    return %w[ongoing url] if inbox&.inbox_type == 'Website'
    return [] unless Campaigns::ChannelDriverResolver.supported?(inbox)

    (Campaigns::ChannelDriverResolver.resolve(self).capabilities + %w[one_off ongoing]).uniq
  end

  private

  def set_display_id
    reload
  end

  def validate_campaign_inbox
    return unless inbox

    if inbox.inbox_type == 'Website'
      errors.add(:inbox, 'Website inbox only supports recurring campaigns') if one_off?
      return
    end

    return if Campaigns::ChannelDriverResolver.supported?(inbox)

    errors.add :inbox, 'Unsupported Inbox type'
  end

  def validate_channel_message_attributes
    return unless Campaigns::ChannelDriverResolver.supported?(inbox)

    Campaigns::ChannelDriverResolver.resolve(self).validation_errors.each do |message|
      errors.add(:message_attributes, message)
    end
  end

  def validate_outbound_audience
    return unless Campaigns::ChannelDriverResolver.supported?(inbox)
    return if Array(audience).present?

    errors.add(:audience, 'at least one audience label is required')
  end

  def ensure_correct_campaign_attributes
    return if inbox.blank?

    if new_record? && !@campaign_type_explicitly_set
      inferred_type = inbox.inbox_type == 'Website' ? self.class.campaign_types[:ongoing] : self.class.campaign_types[:one_off]
      write_attribute(:campaign_type, inferred_type)
    end

    if one_off?
      self.scheduled_at ||= Time.now.utc
    else
      self.scheduled_at = nil
    end
  end

  def validate_url
    return unless inbox&.inbox_type == 'Website'
    return unless ongoing?
    return unless trigger_rules['url']

    use_http_protocol = trigger_rules['url'].starts_with?('http://') || trigger_rules['url'].starts_with?('https://')
    errors.add(:url, 'invalid') unless use_http_protocol
  end

  def prevent_completed_campaign_from_update
    errors.add :status, 'The campaign is already completed' if !campaign_status_changed? && completed?
  end

  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end
end
