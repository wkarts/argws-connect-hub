require 'rails_helper'

RSpec.describe Conversations::ForwardMessageJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'forward-instance',
        'api_key' => 'instance-token'
      }
    )
  end
  let(:source_contact) do
    create(:contact, account: account, phone_number: '+5575988881111')
  end
  let(:source_contact_inbox) do
    create(
      :contact_inbox,
      contact: source_contact,
      inbox: channel.inbox,
      source_id: '5575988881111'
    )
  end
  let(:source_conversation) do
    create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: source_contact,
      contact_inbox: source_contact_inbox
    )
  end
  let(:source_message) do
    create(
      :message,
      account: account,
      inbox: channel.inbox,
      conversation: source_conversation,
      message_type: :incoming,
      content: 'Mensagem encaminhada'
    )
  end
  let(:target_contact) do
    create(:contact, account: account, phone_number: '+5575999992222')
  end
  let(:payload) do
    {
      user_id: user.id,
      account_id: account.id,
      message_id: source_message.id,
      contacts: [target_contact.id],
      operation_id: 'forward-op-1'
    }
  end

  it 'creates a forwarded outgoing message, queues delivery and returns the destination display id' do
    source_message
    clear_enqueued_jobs

    result = nil
    expect do
      result = described_class.perform_now(payload).first
    end.to have_enqueued_job(SendReplyJob)

    destination = account.conversations.find_by!(display_id: result[:conversation_id])
    forwarded = destination.messages.find(result[:message_id])

    expect(destination.contact_id).to eq(target_contact.id)
    expect(destination.inbox_id).to eq(channel.inbox.id)
    expect(forwarded.content).to eq('Mensagem encaminhada')
    expect(forwarded.outgoing?).to be(true)
    expect(forwarded.additional_attributes).to include(
      'forwarded' => true,
      'forward_operation_id' => 'forward-op-1',
      'forwarded_from_message_id' => source_message.id,
      'forwarded_to_contact_id' => target_contact.id,
      'forwarded_by_user_id' => user.id
    )
  end

  it 'is idempotent for the same source user and destination' do
    first = described_class.perform_now(payload).first
    second = described_class.perform_now(payload).first

    expect(second[:conversation_id]).to eq(first[:conversation_id])
    expect(second[:message_id]).to eq(first[:message_id])

    destination = account.conversations.find_by!(display_id: first[:conversation_id])
    matching = destination.messages.where(
      "additional_attributes @> ?",
      {
        forwarded_from_message_id: source_message.id,
        forwarded_to_contact_id: target_contact.id,
        forwarded_by_user_id: user.id
      }.to_json
    )
    expect(matching.count).to eq(1)
  end

  it 'allows the user to forward the same source again in a new operation' do
    first = described_class.perform_now(payload).first
    second = described_class.perform_now(payload.merge(operation_id: 'forward-op-2')).first

    expect(second[:message_id]).not_to eq(first[:message_id])

    destination = account.conversations.find_by!(display_id: first[:conversation_id])
    expect(destination.messages.where("additional_attributes ->> 'forwarded_from_message_id' = ?", source_message.id.to_s).count).to eq(2)
  end

  it 'does not hide a new forwarded message inside an old resolved conversation' do
    target_inbox = create(
      :contact_inbox,
      contact: target_contact,
      inbox: channel.inbox,
      source_id: '5575999992222'
    )
    old_conversation = create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: target_contact,
      contact_inbox: target_inbox,
      status: :resolved
    )

    result = described_class.perform_now(payload).first

    expect(result[:conversation_db_id]).not_to eq(old_conversation.id)
    expect(Conversation.find(result[:conversation_db_id])).not_to be_resolved
  end

  it 'copies attachments without moving the original blob' do
    file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    attachment = source_message.attachments.create!(
      account_id: account.id,
      file_type: :image,
      file: file
    )

    result = described_class.perform_now(payload).first
    forwarded = Message.find(result[:message_id])

    expect(forwarded.attachments.size).to eq(1)
    expect(forwarded.attachments.first.file.blob_id).to eq(attachment.file.blob_id)
    expect(source_message.reload.attachments.size).to eq(1)
  end
end
