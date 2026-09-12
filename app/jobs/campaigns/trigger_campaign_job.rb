# frozen_string_literal: true

class Campaigns::TriggerCampaignJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(campaign_id, expected_scheduled_at = nil)
    campaign = Campaign.find_by(id: campaign_id)
    return if campaign.blank?
    return unless acquire_lock(campaign.id)

    campaign.reload
    return unless campaign.active? && campaign.enabled? && campaign.scheduled_delivery?
    return if campaign.scheduled_at.blank? || campaign.scheduled_at.future?
    return unless expected_schedule_matches?(campaign, expected_scheduled_at)

    campaign.trigger!
  ensure
    release_lock(campaign_id) if @lock_acquired
  end

  private

  def expected_schedule_matches?(campaign, expected_scheduled_at)
    return true if expected_scheduled_at.blank?

    expected = Time.zone.parse(expected_scheduled_at.to_s)
    expected.present? && campaign.scheduled_at.to_f == expected.to_f
  rescue ArgumentError, TypeError
    false
  end

  def acquire_lock(campaign_id)
    @lock_acquired = ActiveRecord::Base.connection.select_value(
      "SELECT pg_try_advisory_lock(#{Integer(campaign_id)})"
    )
    ActiveModel::Type::Boolean.new.cast(@lock_acquired)
  end

  def release_lock(campaign_id)
    ActiveRecord::Base.connection.select_value(
      "SELECT pg_advisory_unlock(#{Integer(campaign_id)})"
    )
    @lock_acquired = false
  rescue StandardError => e
    Rails.logger.warn("Could not release campaign advisory lock #{campaign_id}: #{e.message}")
  end
end
