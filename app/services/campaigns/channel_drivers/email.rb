# frozen_string_literal: true

class Campaigns::ChannelDrivers::Email < Campaigns::ChannelDrivers::Base
  def deliverable?(contact)
    contact.email.present?
  end

  def deliver(contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return if contact_inbox.blank?

    Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign.display_id,
      conversation_additional_attributes: { 'mail_subject' => subject },
      custom_attributes: {},
      message_attributes: {},
      skip_existing_conversation: false
    ).perform
  end

  def capabilities
    %w[subject text variables].freeze
  end

  def validation_errors
    return [] if subject.present?

    ['subject is required for email campaigns']
  end

  private

  def subject
    campaign.message_attributes.to_h['subject'].to_s.strip
  end
end
