class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return if message.outgoing? && message.source_id.present? # is message send by own

    if channel.provider == 'connectapi' && message.conversation.whatsapp_group? && !channel.groups_enabled?
      message.update!(status: :failed, external_error: 'Grupos de WhatsApp estão desabilitados nesta caixa de entrada.')
      return
    end

    group = Whatsapp::Groups::Access.group_for(message.conversation)
    if group && (group.management? || !group.active? || (message.sender.is_a?(User) && !group.allowed?(message.sender)))
      message.update!(status: :failed, external_error: 'Tratamento do grupo alterado ou acesso revogado. Mensagem não enviada.')
      return
    end

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
    if message_id.present?
      message.update!(source_id: message_id)
      schedule_connect_api_receipt_watch
    end
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
    if message_id.present?
      message.update!(source_id: message_id)
      schedule_connect_api_receipt_watch
    end
  end

  def schedule_connect_api_receipt_watch
    return unless channel.provider == 'connectapi'

    Channels::Whatsapp::ConnectApiReceiptWatchJob
      .set(wait: Channels::Whatsapp::ConnectApiReceiptWatchJob::CHECK_DELAYS.first.seconds)
      .perform_later(message.id, 0)

    HubDiagnostics::Recorder.emit(
      'receipt.watch_started',
      HubDiagnostics::Recorder.message_attributes(message).merge(
        component: 'connectapi_receipt',
        channel_id: message.inbox.channel.id
      )
    )
  rescue StandardError => e
    Rails.logger.warn("[HUB Connect|API] receipt watcher scheduling failed: #{e.class}: #{e.message}")
  end

  def campaign_freeform_message?
    attributes = message.additional_attributes.to_h
    attributes['campaign_id'].present? && template_params.blank?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
