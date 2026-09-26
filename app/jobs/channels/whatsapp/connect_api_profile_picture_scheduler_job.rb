# frozen_string_literal: true

class Channels::Whatsapp::ConnectApiProfilePictureSchedulerJob < ApplicationJob
  queue_as :low

  MAX_CONTACTS_PER_CHANNEL = 200
  POSITIVE_CACHE = 12.hours
  NEGATIVE_CACHE = 15.minutes
  GROUP_CACHE = 6.hours
  MAX_GROUPS_PER_CHANNEL = 100

  def perform
    Channel::Whatsapp.where(provider: 'connectapi').includes(:inbox).find_each do |channel|
      next unless channel.inbox
      next if ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])

      channel.inbox.contact_inboxes
             .includes(:contact)
             .order(updated_at: :desc)
             .limit(MAX_CONTACTS_PER_CHANNEL)
             .each do |contact_inbox|
        contact = contact_inbox.contact
        next unless contact
        next if profile_check_fresh?(contact)

        Channels::Whatsapp::ConnectApiProfilePictureJob.perform_later(contact.id, channel.id)
      end

      WhatsappGroup.where(inbox_id: channel.inbox.id)
                   .where('profile_picture_checked_at IS NULL OR profile_picture_checked_at < ?', GROUP_CACHE.ago)
                   .order(Arel.sql('last_activity_at DESC NULLS LAST, id DESC'))
                   .limit(MAX_GROUPS_PER_CHANNEL)
                   .pluck(:id)
                   .each { |group_id| Whatsapp::Groups::ProfilePictureJob.perform_later(group_id) }
    end
  end

  private

  def profile_check_fresh?(contact)
    value = contact.additional_attributes.to_h.dig('connect_api', 'profile_picture_checked_at')
    checked_at = Time.zone.parse(value.to_s)
    return false if checked_at.blank?

    cache_window = contact.avatar.attached? ? POSITIVE_CACHE : NEGATIVE_CACHE
    checked_at > cache_window.ago
  rescue ArgumentError, TypeError
    false
  end
end
