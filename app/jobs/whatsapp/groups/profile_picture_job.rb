# frozen_string_literal: true

class Whatsapp::Groups::ProfilePictureJob < ApplicationJob
  queue_as :low

  MAX_BYTES = 5.megabytes

  def perform(group_id)
    group = WhatsappGroup.includes(:inbox).find_by(id: group_id)
    return unless group&.inbox&.whatsapp?
    return unless group.inbox.channel.provider == 'connectapi'

    url = Whatsapp::Groups::Provider.new(group.inbox).profile_picture_url(group)
    group.update_column(:profile_picture_checked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    return if url.blank?

    file = Down.download(url, max_size: MAX_BYTES)
    group.avatar.attach(
      io: file,
      filename: File.basename(file.respond_to?(:original_filename) ? file.original_filename.to_s : 'group-avatar.jpg').presence || 'group-avatar.jpg',
      content_type: file.content_type
    )
    Whatsapp::Groups::BroadcastJob.perform_later(group.id, nil, nil, [], false)
  rescue ConnectApi::Error => e
    group&.update_column(:profile_picture_checked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn("[HUB groups] group avatar lookup failed group=#{group_id}: #{e.message}")
    raise if e.status.to_i >= 500 || e.status.to_i.zero?
  rescue Down::Error => e
    group&.update_column(:profile_picture_checked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn("[HUB groups] group avatar download failed group=#{group_id}: #{e.class}: #{e.message}")
  end
end
