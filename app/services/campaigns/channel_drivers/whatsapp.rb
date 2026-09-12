# frozen_string_literal: true

class Campaigns::ChannelDrivers::Whatsapp < Campaigns::ChannelDrivers::Base
  def deliverable?(contact)
    contact.phone_number.present?
  end

  def deliver(contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return if contact_inbox.blank?

    Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign.display_id,
      conversation_additional_attributes: {},
      custom_attributes: {},
      message_attributes: { template_params: template_params },
      skip_existing_conversation: false
    ).perform
  end

  def capabilities
    %w[text template variables].freeze
  end

  def validation_errors
    return [] if template_params.present?

    ['template_params is required for WhatsApp campaigns']
  end

  private

  def template_params
    campaign.message_attributes.to_h['template_params']
  end
end
