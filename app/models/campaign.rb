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

  RECURRENCE_FREQUENCIES = %w[hourly daily weekly monthly].freeze

  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :title, presence: true
  validate :validate_campaign_content
  validate :validate_campaign_inbox
  validate :validate_channel_message_attributes
  validate :validate_schedule
  validate :validate_recurrence
  validate :validate_url
  validate :prevent_completed_campaign_from_update, on: :update

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true

  enum campaign_type: { ongoing: 0, one_off: 1 }
  enum campaign_status: { active: 0, completed: 1 }

  has_many :conversations, dependent: :nullify, autosave: true
  has_many_attached :materials

  before_validation :ensure_correct_campaign_attributes
  after_commit :set_display_id, unless: :display_id?
  after_commit :enqueue_scheduled_delivery, on: [:create, :update]

  def campaign_type=(value)
    @campaign_type_explicitly_set = true
    super
  end

  def trigger!
    return if completed? || !enabled?

    if one_off?
      Campaigns::OneoffCampaignService.new(campaign: self).perform
    elsif scheduled_recurring_delivery?
      Campaigns::RecurringCampaignService.new(campaign: self).perform
    end
  end

  def channel_capabilities
    return %w[ongoing url schedule materials] if inbox&.inbox_type == 'Website'
    return [] unless Campaigns::ChannelDriverResolver.supported?(inbox)

    (Campaigns::ChannelDriverResolver.resolve(self).capabilities + %w[one_off ongoing schedule materials]).uniq
  end

  def recurrence_config
    trigger_rules.to_h['recurrence'].to_h
  end

  def scheduled_delivery?
    return false unless Campaigns::ChannelDriverResolver.supported?(inbox)
    return true if one_off?

    scheduled_recurring_delivery?
  end

  def scheduled_recurring_delivery?
    ongoing? && Campaigns::ChannelDriverResolver.supported?(inbox) && recurrence_config['frequency'].present?
  end

  def next_scheduled_at(from: scheduled_at || Time.current)
    return unless scheduled_recurring_delivery?

    interval = [recurrence_config['interval'].to_i, 1].max
    next_time = case recurrence_config['frequency']
                when 'hourly' then from + interval.hours
                when 'daily' then from + interval.days
                when 'weekly' then from + interval.weeks
                when 'monthly' then from.advance(months: interval)
                end
    return if next_time.blank?

    ends_at = recurrence_ends_at
    return if ends_at.present? && next_time > ends_at

    next_time
  end

  def recurrence_ends_at
    value = recurrence_config['ends_at']
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  private

  def set_display_id
    reload
  end

  def validate_campaign_content
    return if message.present? || materials.attached?

    errors.add(:message, 'or at least one campaign material is required')
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

  def validate_schedule
    errors.add(:scheduled_at, 'is required') if scheduled_at.blank?
  end

  def validate_recurrence
    return unless ongoing? && Campaigns::ChannelDriverResolver.supported?(inbox)

    frequency = recurrence_config['frequency'].to_s
    unless RECURRENCE_FREQUENCIES.include?(frequency)
      errors.add(:trigger_rules, "recurrence frequency must be one of: #{RECURRENCE_FREQUENCIES.join(', ')}")
      return
    end

    errors.add(:trigger_rules, 'recurrence interval must be greater than zero') if recurrence_config['interval'].to_i <= 0

    ends_at_value = recurrence_config['ends_at']
    return if ends_at_value.blank?

    ends_at = recurrence_ends_at
    if ends_at.blank?
      errors.add(:trigger_rules, 'recurrence end date is invalid')
    elsif scheduled_at.present? && ends_at < scheduled_at
      errors.add(:trigger_rules, 'recurrence end date must be after the first scheduled execution')
    end
  end

  def ensure_correct_campaign_attributes
    return if inbox.blank?

    if new_record? && !@campaign_type_explicitly_set
      inferred_type = inbox.inbox_type == 'Website' ? self.class.campaign_types[:ongoing] : self.class.campaign_types[:one_off]
      write_attribute(:campaign_type, inferred_type)
    end

    self.scheduled_at ||= Time.current
  end

  def validate_url
    return unless inbox&.inbox_type == 'Website'
    return unless ongoing?
    return unless trigger_rules.to_h['url']

    url = trigger_rules.to_h['url']
    use_http_protocol = url.starts_with?('http://') || url.starts_with?('https://')
    errors.add(:url, 'invalid') unless use_http_protocol
  end

  def prevent_completed_campaign_from_update
    errors.add :status, 'The campaign is already completed' if !campaign_status_changed? && completed?
  end

  def enqueue_scheduled_delivery
    return unless active? && enabled? && scheduled_delivery? && scheduled_at.present?
    return unless previous_changes.key?('id') || previous_changes.key?('scheduled_at') || previous_changes.key?('enabled') || previous_changes.key?('campaign_status')

    Campaigns::TriggerCampaignJob.set(wait_until: [scheduled_at, Time.current].max).perform_later(id, scheduled_at.iso8601(6))
  end

  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end
end
