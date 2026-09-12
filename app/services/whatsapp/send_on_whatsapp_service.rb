class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return if message.message_type == :outgoing && message.source_id&.is_present? # is message send by own

    Whatsapp::ConnectApiOpeningMessageValidator.new(message).validate!

    should_send_template_message = !campaign_freeform_message? && (template_params.present? || !message.conversation.can_reply?)
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  rescue Whatsapp::ConnectApiOpeningMessageValidator::Error => e
    message.update!(status: :failed, external_error: e.message)
  end

  def send_template_message
    name, namespace, lang_code, processed_parameters = processable_channel_message_template

    return if name.blank?

    message_id = channel.send_template(message, message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       })
    message.update!(source_id: message_id) if message_id.present?
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  def processable_channel_message_template
    if template_params.present?
      return [
        template_params['name'],
        template_params['namespace'],
        template_params['language'],
        template_params['processed_params']&.map { |_, value| { type: 'text', text: value } }
      ]
    end

    # Connect|API never infers a template from free text, bypassing the catalog.
    return [nil, nil, nil, nil] if channel.provider == 'connectapi'

    channel.message_templates&.each do |template|
      match_obj = template_match_object(template)
      next if match_obj.blank?

      processed_parameters = match_obj.captures.map { |x| { type: 'text', text: x } }
      return [template['name'], template['namespace'], template['language'], processed_parameters]
    end
    [nil, nil, nil, nil]
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def template_match_object(template)
    body_object = validated_body_object(template)
    return if body_object.blank?

    template_match_regex = build_template_match_regex(body_object['text'])
    message.content.match(template_match_regex)
  end

  def build_template_match_regex(template_text)
    template_text = template_text.gsub(/{{\d}}/, '(.*)')
    template_text = Regexp.escape(template_text)
    template_text = template_text.gsub(Regexp.escape('(.*)'), '(.*)')

    template_match_string = "^#{template_text}$"
    Regexp.new template_match_string
  end

  def validated_body_object(template)
    return if template['status'] != 'approved'

    template['components'].find { |obj| obj['type'] == 'BODY' && obj.key?('text') }
  end

  def send_session_message
    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    phone_number = if uuid_regex.match?(message.conversation.contact_inbox.source_id)
                     message.conversation.contact_inbox.contact.phone_number.sub('+', '')
                   else
                     message.conversation.contact_inbox.source_id
                   end
    message_id = channel.send_message(phone_number, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def campaign_freeform_message?
    attributes = message.additional_attributes.to_h
    attributes['campaign_id'].present? && template_params.blank?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
