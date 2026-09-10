# frozen_string_literal: true

require 'cgi'

class Channels::Whatsapp::ConnectApiProfilePictureJob < ApplicationJob
  queue_as :low

  CHECK_INTERVAL = 12.hours

  def perform(contact_id, channel_id, force: false)
    contact = Contact.find_by(id: contact_id)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return unless contact && channel&.inbox
    return if manual_instance_deletion?(channel)

    attributes = contact.additional_attributes.to_h.deep_stringify_keys
    connect_api = attributes.fetch('connect_api', {}).to_h.deep_stringify_keys
    return if !force && fresh_check?(connect_api['profile_picture_checked_at']) && contact.avatar.attached?

    profile_url = resolve_profile_picture(channel, contact)
    connect_api['profile_picture_checked_at'] = Time.current.utc.iso8601

    if profile_url.present?
      connect_api['profile_picture'] = profile_url
      connect_api.delete('profile_picture_error')
      contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
        additional_attributes: attributes.merge('connect_api' => connect_api),
        updated_at: Time.current
      )
      ::Avatar::AvatarFromUrlJob.perform_later(contact, profile_url)
    else
      contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
        additional_attributes: attributes.merge('connect_api' => connect_api),
        updated_at: Time.current
      )
    end
  rescue ConnectApi::Error => e
    Rails.logger.warn("[HUB Connect|API] profile picture lookup failed contact=#{contact_id}: #{e.message}")
    raise if e.status.to_i >= 500 || e.status.to_i == 0
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] profile picture job failed contact=#{contact_id}: #{e.class}: #{e.message}")
    raise
  end

  private

  def resolve_profile_picture(channel, contact)
    instance_name = channel.provider_config.to_h['instance_name'].to_s
    return if instance_name.blank?

    numbers_for(channel, contact).each do |number|
      result = client.request(
        :post,
        "/chat/fetchProfilePictureUrl/#{CGI.escape(instance_name)}",
        body: { number: number }
      )
      data = result.respond_to?(:deep_stringify_keys) ? result.deep_stringify_keys : {}
      url = data['profilePictureUrl'].to_s.presence || data.dig('data', 'profilePictureUrl').to_s.presence || data['url'].to_s.presence
      return url if url.present?
    rescue ConnectApi::Error => e
      next if [400, 404, 422].include?(e.status.to_i)

      raise
    end

    nil
  end

  def numbers_for(channel, contact)
    contact_inbox = contact.contact_inboxes.find_by(inbox_id: channel.inbox.id)
    attributes = contact.additional_attributes.to_h.deep_stringify_keys
    aliases = Array(attributes.dig('connect_api', 'aliases'))

    values = [contact.phone_number, contact_inbox&.source_id, *aliases]
    digits = values.filter_map do |value|
      number = value.to_s.split('@', 2).first.to_s.gsub(/\D/, '')
      number.presence
    end

    digits.flat_map { |number| brazilian_variants(number) }.uniq
  end

  def brazilian_variants(number)
    values = [number]
    return values unless number.start_with?('55')

    # Brazil mobile identifiers can appear with or without the ninth digit in
    # legacy PN mappings. Keep both as lookup candidates without changing the
    # canonical contact stored by HUB.
    if number.length == 12
      values << "#{number[0, 4]}9#{number[4..]}"
    elsif number.length == 13 && number[4] == '9'
      values << "#{number[0, 4]}#{number[5..]}"
    end

    values
  end

  def fresh_check?(value)
    checked_at = Time.zone.parse(value.to_s)
    checked_at.present? && checked_at > CHECK_INTERVAL.ago
  rescue ArgumentError, TypeError
    false
  end

  def manual_instance_deletion?(channel)
    ActiveModel::Type::Boolean.new.cast(channel.provider_config.to_h['connect_api_manual_deletion'])
  end

  def client
    @client ||= ConnectApi::Client.new
  end
end
