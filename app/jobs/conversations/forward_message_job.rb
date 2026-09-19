class Conversations::ForwardMessageJob < ApplicationJob
  queue_as :default

  def perform(payload)
    payload = payload.to_h.with_indifferent_access
    @user = User.find(payload[:user_id])
    @account = Account.find(payload[:account_id])
    @message = Message.find_by!(id: payload[:message_id], account_id: @account.id)
    @contacts = Array(payload[:contacts]).map(&:to_i).uniq

    return [] if @contacts.empty?

    @contacts.map do |contact_id|
      forward_to_contact(contact_id)
    end
  end

  private

  def forward_to_contact(contact_id)
    contact = @account.contacts.find(contact_id)
    forwarded_message = existing_forwarded_message(contact)

    if forwarded_message
      conversation = forwarded_message.conversation
    else
      conversation = forward_conversation(contact)
      forwarded_message = conversation.messages.build(message_params(contact))
      process_attachments(forwarded_message)
      forwarded_message.save!
    end

    {
      contact_id: contact.id,
      conversation_id: conversation.display_id,
      conversation_db_id: conversation.id,
      message_id: forwarded_message.id
    }
  end

  def message_params(contact)
    {
      account_id: @account.id,
      inbox_id: @message.inbox_id,
      content: @message.content,
      message_type: :outgoing,
      sender: @user,
      additional_attributes: {
        'forwarded' => true,
        'forwarded_from_message_id' => @message.id,
        'forwarded_to_contact_id' => contact.id,
        'forwarded_by_user_id' => @user.id
      }
    }
  end

  def create_contact_inbox(contact)
    ::ContactInboxBuilder.new(
      contact: contact,
      inbox: @message.inbox,
      hmac_verified: true
    ).perform
  end

  def conversation_params(contact, contact_inbox)
    {
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id,
      account_id: @account.id,
      inbox_id: @message.inbox_id,
      assignee_id: @user.id
    }
  end

  def forward_conversation(contact)
    contact_inbox = create_contact_inbox(contact)

    active = contact_inbox.conversations
                          .where.not(status: :resolved)
                          .order(last_activity_at: :desc, id: :desc)
                          .first
    return active if active

    ::Conversation.create!(conversation_params(contact, contact_inbox))
  end

  def existing_forwarded_message(contact)
    marker = {
      forwarded_from_message_id: @message.id,
      forwarded_to_contact_id: contact.id,
      forwarded_by_user_id: @user.id
    }

    Message.joins(:conversation)
           .where(account_id: @account.id, inbox_id: @message.inbox_id, message_type: :outgoing)
           .where(conversations: { contact_id: contact.id })
           .where('messages.additional_attributes @> ?', marker.to_json)
           .order('messages.id DESC')
           .first
  end

  def process_attachments(message)
    return if @message.attachments.blank?

    @message.attachments.each do |attachment|
      attach_file(message, attachment)
      attach_location(message, attachment)
      attach_contact(message, attachment)
    end
  end

  def attach_file(message, attachment)
    return unless %w[image audio video file].include?(attachment.file_type)
    return unless attachment.file.attached?

    message.attachments.new(
      account_id: @account.id,
      file_type: attachment.file_type,
      file: attachment.file.blob
    )
  end

  def attach_location(message, attachment)
    return unless attachment.file_type == 'location'

    message.attachments.new(
      account_id: @account.id,
      file_type: attachment.file_type,
      coordinates_lat: attachment.coordinates_lat,
      coordinates_long: attachment.coordinates_long,
      fallback_title: attachment.fallback_title,
      external_url: attachment.external_url
    )
  end

  def attach_contact(message, attachment)
    return unless attachment.file_type == 'contact'

    message.attachments.new(
      account_id: @account.id,
      file_type: attachment.file_type,
      fallback_title: attachment.fallback_title
    )
  end
end
