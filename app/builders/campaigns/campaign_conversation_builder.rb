class Campaigns::CampaignConversationBuilder
  pattr_initialize [
    :contact_inbox_id!,
    :campaign_display_id!,
    :conversation_additional_attributes,
    :custom_attributes,
    :message_attributes,
    { skip_existing_conversation: true }
  ]

  def perform
    @contact_inbox = ContactInbox.find(@contact_inbox_id)
    @campaign = @contact_inbox.inbox.campaigns.find_by!(display_id: campaign_display_id)

    ActiveRecord::Base.transaction do
      @contact_inbox.lock!

      if skip_existing_conversation && @contact_inbox.reload.conversations.present?
        raise 'Conversation already present'
      end

      @conversation = ::Conversation.create!(conversation_params)
      Messages::MessageBuilder.new(@campaign.sender, @conversation, message_params).perform
    end
    @conversation
  rescue StandardError => e
    Rails.logger.info(e.message)
    nil
  end

  private

  def message_params
    persisted_attributes = @campaign.message_attributes || {}
    attributes = (message_attributes.presence || persisted_attributes).to_h.deep_symbolize_keys
    ActionController::Parameters.new(
      {
        content: @campaign.message,
        campaign_id: @campaign.id
      }.merge(attributes)
    )
  end

  def conversation_params
    {
      account_id: @campaign.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      campaign_id: @campaign.id,
      additional_attributes: conversation_additional_attributes,
      custom_attributes: custom_attributes || {}
    }
  end
end
