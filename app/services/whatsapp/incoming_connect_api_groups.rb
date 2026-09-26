# frozen_string_literal: true

# Group identities never pass through phone-number normalization. The sender is
# the participant; the conversation/contact-inbox belongs to the group JID.
module Whatsapp::IncomingConnectApiGroups
  private

  def group_jid
    candidates = [@processed_params.dig(:contacts, 0, :group_id), @processed_params.dig(:messages, 0, :connect_api, :remote_jid)]
    candidates.find { |value| value.to_s.match?(/\A\d+(?:-\d+)?@g\.us\z/) }
  end

  def group_message?
    group_jid.present?
  end

  def process_messages
    declared_group = @processed_params.dig(:contacts, 0, :group_id).present? ||
                     @processed_params.dig(:messages, 0, :connect_api, :remote_jid).to_s.end_with?('@g.us')
    # Never reinterpret a malformed/disabled group address as a person's phone.
    return if declared_group && (!group_message? || !inbox.channel.groups_enabled?)

    super
  end

  def message_content(message)
    return super unless group_message? && %w[image audio video document sticker].include?(message[:type].to_s)

    caption = message[message[:type]].to_h.with_indifferent_access[:caption].presence
    caption && !outgoing_message_type? && @sender ? "*#{@sender.name}*: #{caption}" : caption
  end

  def set_contact
    return super unless group_message?

    # HashWithIndifferentAccess#to_h returns string keys; preserve symbol access
    # for both Meta-compatible envelopes and native recovery metadata.
    contact_params = @processed_params.dig(:contacts, 0).to_h.with_indifferent_access
    context = @processed_params.dig(:messages, 0, :connect_api).to_h.with_indifferent_access
    @contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox, source_id: group_jid,
      contact_attributes: {
        identifier: "whatsapp-group:#{inbox.id}:#{group_jid}",
        name: contact_params[:group_subject].presence || context[:group_subject].presence || group_jid,
        additional_attributes: { 'whatsapp_group' => true, 'group_jid' => group_jid }
      }
    ).perform
    @contact = @contact_inbox.contact
    @sender = nil
    unless outgoing_message_type?
      participant = context[:participant_alt].presence || context[:participant].presence || contact_params[:wa_id].to_s
      phone = participant.to_s.match?(/\A\d+(?:@(s\.whatsapp\.net|c\.us))?\z/) ? participant.split('@').first : nil
      name = contact_params.dig(:profile, :name).presence || participant.presence || 'Participante'
      if phone.present?
        @sender = ContactInboxWithContactBuilder.new(
          inbox: inbox, source_id: phone,
          contact_attributes: { name: name, phone_number: "+#{phone}" }
        ).perform.contact
      elsif participant.to_s.match?(/\A\d+@lid\z/)
        @sender = inbox.account.contacts.find_or_create_by!(identifier: "whatsapp-participant:#{inbox.id}:#{participant}") { |contact| contact.name = name }
      end
    end
    subject = contact_params[:group_subject].presence || context[:group_subject].presence
    @contact.update!(name: subject) if subject.present? && @contact.name != subject
  end

  def conversation_params
    values = super
    return values unless group_message?

    values.merge(additional_attributes: { 'is_group' => true, 'group_jid' => group_jid })
  end

  def set_conversation
    super
    return unless group_message? && @conversation
    return if @conversation.additional_attributes.to_h['group_jid'] == group_jid

    @conversation.update!(additional_attributes: @conversation.additional_attributes.to_h.merge('is_group' => true, 'group_jid' => group_jid))
  end

  def create_message(message)
    super
    return @message unless group_message?

    context = message[:connect_api].to_h.with_indifferent_access
    @message.content_attributes = @message.content_attributes.to_h.merge(
      'whatsapp_group' => true, 'group_jid' => group_jid,
      'group_participant' => context[:participant_alt].presence || context[:participant].presence
    ).compact
    @message
  end
end
