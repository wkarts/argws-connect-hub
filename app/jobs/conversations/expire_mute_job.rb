# frozen_string_literal: true

class Conversations::ExpireMuteJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, expected_muted_until)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    mute = conversation.contact.additional_attributes.to_h.deep_stringify_keys['hub_mute'].to_h
    return if mute.blank?
    return unless mute['muted_until'].to_s == expected_muted_until.to_s

    expires_at = Time.iso8601(mute['muted_until'].to_s)
    if expires_at.future?
      self.class.set(wait_until: expires_at).perform_later(conversation_id, expected_muted_until)
      return
    end

    conversation.unmute!
  rescue ArgumentError
    Rails.logger.warn(
      "[HUB mute] invalid mute expiration conversation=#{conversation_id} value=#{expected_muted_until}"
    )
  end
end
