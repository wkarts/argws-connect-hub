# frozen_string_literal: true

class Campaigns::ChannelDrivers::Api < Campaigns::ChannelDrivers::Base
  def deliverable?(_contact)
    true
  end

  def deliver(contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return if contact_inbox.blank?

    Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign.display_id,
      conversation_additional_attributes: {},
      custom_attributes: {},
      message_attributes: {},
      skip_existing_conversation: false
    ).perform
  end

  def capabilities
    %w[text json webhook variables].freeze
  end

  def validation_errors
    return [] if channel.webhook_url.present?

    ['webhook_url is required for API campaigns']
  end
end
