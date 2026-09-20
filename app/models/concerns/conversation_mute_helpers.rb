# frozen_string_literal: true

module ConversationMuteHelpers
  extend ActiveSupport::Concern

  MUTE_ATTRIBUTE = 'hub_mute'.freeze
  ALLOWED_MUTE_DURATIONS = [1800, 3600, 7200, 21_600, 28_800].freeze

  def mute!(duration_seconds: nil)
    seconds = normalized_mute_duration(duration_seconds)
    attributes = contact.additional_attributes.to_h.deep_dup
    attributes[MUTE_ATTRIBUTE] = {
      'muted' => true,
      'muted_at' => Time.current.utc.iso8601,
      'muted_until' => seconds ? (Time.current + seconds.seconds).utc.iso8601 : nil
    }

    contact.update!(additional_attributes: attributes)
    create_muted_message
    dispatch_conversation_updated_event('muted' => [false, true])
    schedule_mute_expiration(seconds, attributes[MUTE_ATTRIBUTE]['muted_until'])
  end

  def unmute!
    attributes = contact.additional_attributes.to_h.deep_dup
    had_hub_mute = attributes.delete(MUTE_ATTRIBUTE).present?

    if had_hub_mute
      contact.update!(additional_attributes: attributes)
    elsif contact.blocked?
      # Compatibilidade com o comportamento legado do HUB, que implementava
      # "silenciar" bloqueando o contato. Novos silenciamentos nunca alteram
      # contact.blocked.
      contact.update!(blocked: false)
    end

    create_unmuted_message
    dispatch_conversation_updated_event('muted' => [true, false])
  end

  def muted?
    mute = contact.additional_attributes.to_h.deep_stringify_keys[MUTE_ATTRIBUTE].to_h
    return contact.blocked? if mute.blank?
    return false unless ActiveModel::Type::Boolean.new.cast(mute.fetch('muted', true))

    muted_until = mute['muted_until'].to_s.presence
    return true if muted_until.blank?

    Time.iso8601(muted_until).future?
  rescue ArgumentError
    false
  end

  def mute_expires_at
    mute = contact.additional_attributes.to_h.deep_stringify_keys[MUTE_ATTRIBUTE].to_h
    value = mute['muted_until'].to_s.presence
    value ? Time.iso8601(value) : nil
  rescue ArgumentError
    nil
  end

  private

  def schedule_mute_expiration(seconds, muted_until)
    return unless seconds && muted_until.present?

    Conversations::ExpireMuteJob
      .set(wait: seconds.seconds)
      .perform_later(id, muted_until)
  end

  def normalized_mute_duration(value)
    return nil if value.blank? || value.to_i.zero?

    seconds = value.to_i
    raise ArgumentError, 'Período de silenciamento inválido.' unless ALLOWED_MUTE_DURATIONS.include?(seconds)

    seconds
  end
end
