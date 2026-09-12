# frozen_string_literal: true

class Campaigns::ChannelDrivers::Whatsapp < Campaigns::ChannelDrivers::Base
  def deliverable?(contact)
    contact.phone_number.present?
  end

  def deliver(contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return if contact_inbox.blank?

    message_attributes = {}
    message_attributes[:template_params] = template_params if template_params.present?

    Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign.display_id,
      conversation_additional_attributes: {},
      custom_attributes: {},
      message_attributes: message_attributes,
      skip_existing_conversation: false
    ).perform
  end

  def capabilities
    %w[text freeform template variables].freeze
  end

  def validation_errors
    return [] if template_params.blank?
    return [] unless channel.provider == 'connectapi'

    template = channel.opening_template_catalog.find_available(
      name: template_params['name'],
      language: template_params['language'],
      opening_only: false
    )
    return ['selected template is not available for this Connect|API instance'] if template.blank?

    if ConnectApi::LocalTemplateMessage.local?(template)
      begin
        ConnectApi::LocalTemplateMessage.new(template, template_params).validate_content!(campaign.message)
      rescue ConnectApi::LocalTemplateMessage::Error => e
        return [e.message]
      end
    end

    []
  end

  private

  def template_params
    campaign.message_attributes.to_h['template_params']
  end
end
