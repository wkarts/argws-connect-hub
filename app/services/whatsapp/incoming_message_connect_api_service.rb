# frozen_string_literal: true

# Connect|API emits Meta Cloud-compatible webhook envelopes for HUB.
#
# This adapter keeps the Meta-compatible processing intact while adding the
# Connect|API-specific guarantees HUB needs:
# - phone-number identity remains canonical across PN/LID aliases;
# - WhatsApp push name/profile picture refresh generic HUB contacts;
# - only one active conversation is kept for a contact/inbox;
# - messages emitted by the linked WhatsApp device remain outgoing messages.
class Whatsapp::IncomingMessageConnectApiService < Whatsapp::IncomingMessageWhatsappCloudService
  private

  def set_contact
    super
    return unless @contact

    refresh_connect_api_contact!
  end

  def set_conversation
    super
    return unless @conversation && @contact_inbox

    resolve_duplicate_active_conversations!
  end

  def refresh_connect_api_contact!
    contact_params = @processed_params[:contacts]&.first
    return if contact_params.blank?

    profile_name = contact_params.dig(:profile, :name).to_s.strip
    profile_picture = contact_params.dig(:profile, :picture).to_s.strip
    message_context = @processed_params[:messages]&.first&.dig(:connect_api).to_h.deep_stringify_keys

    changes = {}
    changes[:name] = profile_name if meaningful_profile_name?(profile_name) && generic_contact_name?(@contact)

    current_additional = @contact.additional_attributes.to_h.deep_stringify_keys
    connect_api_attributes = current_additional.fetch('connect_api', {}).to_h.deep_stringify_keys
    aliases = [
      message_context['remote_jid'],
      message_context['remote_jid_alt'],
      message_context['participant'],
      message_context['participant_alt']
    ].compact_blank.uniq

    updated_connect_api = connect_api_attributes.merge(
      'aliases' => (Array(connect_api_attributes['aliases']) + aliases).compact_blank.uniq,
      'last_from_me' => ActiveModel::Type::Boolean.new.cast(message_context['from_me'])
    )
    updated_connect_api['profile_picture'] = profile_picture if profile_picture.present?

    changes[:additional_attributes] = current_additional.merge('connect_api' => updated_connect_api)
    @contact.update!(changes) if changes.present?

    return if profile_picture.blank?
    return if connect_api_attributes['profile_picture'] == profile_picture && @contact.avatar.attached?

    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_picture)
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] contact metadata refresh skipped: #{e.class}: #{e.message}")
  end

  def meaningful_profile_name?(name)
    return false if name.blank?

    digits = name.gsub(/\D/, '')
    digits.blank? || digits.length < 8
  end

  def generic_contact_name?(contact)
    name = contact.name.to_s.strip
    return true if name.blank?

    name_digits = name.gsub(/\D/, '')
    phone_digits = contact.phone_number.to_s.gsub(/\D/, '')
    source_digits = @contact_inbox&.source_id.to_s.gsub(/\D/, '')

    [phone_digits, source_digits].compact_blank.include?(name_digits) || name.match?(/\A\+?\d[\d\s().-]{7,}\z/)
  end

  def resolve_duplicate_active_conversations!
    active_scope = @contact_inbox.conversations.where.not(status: :resolved)
    duplicate_ids = active_scope.where.not(id: @conversation.id).pluck(:id)
    return if duplicate_ids.empty?

    Conversation.where(id: duplicate_ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: Conversation.statuses[:resolved],
      updated_at: Time.current
    )

    Rails.logger.info(
      "[HUB Connect|API] resolved duplicate active conversations contact_inbox=#{@contact_inbox.id} " \
      "kept=#{@conversation.id} resolved=#{duplicate_ids.join(',')}"
    )
  end
end
