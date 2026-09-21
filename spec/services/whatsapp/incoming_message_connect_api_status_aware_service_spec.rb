require 'rails_helper'

describe Whatsapp::IncomingMessageConnectApiStatusAwareService do
  let(:inbox) { create(:inbox) }
  let(:service) { described_class.new(inbox: inbox, params: {}) }

  it 'does not regress delivered to sent' do
    message = create(:message, inbox: inbox, account: inbox.account, status: :delivered)

    expect(message).not_to receive(:save!)
    service.send(:update_message_with_status, message, { status: 'sent' }.with_indifferent_access)
    expect(message.reload.status).to eq('delivered')
  end

  it 'does not regress read to delivered' do
    message = create(:message, inbox: inbox, account: inbox.account, status: :read)

    expect(message).not_to receive(:save!)
    service.send(:update_message_with_status, message, { status: 'delivered' }.with_indifferent_access)
    expect(message.reload.status).to eq('read')
  end

  it 'ignores a late failure after delivery' do
    message = create(:message, inbox: inbox, account: inbox.account, status: :delivered)

    expect(message).not_to receive(:save!)
    service.send(:update_message_with_status, message, { status: 'failed', errors: [{ code: 500, title: 'late' }] }.with_indifferent_access)
    expect(message.reload.status).to eq('delivered')
  end

  it 'allows sent to progress to delivered and read' do
    message = create(:message, inbox: inbox, account: inbox.account, status: :sent)

    service.send(:update_message_with_status, message, { status: 'delivered' }.with_indifferent_access)
    expect(message.reload.status).to eq('delivered')

    service.send(:update_message_with_status, message, { status: 'read' }.with_indifferent_access)
    expect(message.reload.status).to eq('read')
  end

  it 'marks an outgoing message as deleted when revoke comes from the smartphone' do
    message = create(
      :message,
      inbox: inbox,
      account: inbox.account,
      message_type: :outgoing,
      source_id: 'PHONE-DELETE-1',
      content: 'Mensagem enviada',
      content_attributes: { 'link_preview' => { 'url' => 'https://example.com' } }
    )

    service.send(
      :update_message_with_status,
      message,
      { status: 'deleted', timestamp: Time.current.to_i }.with_indifferent_access
    )

    message.reload
    expect(message.deleted).to be(true)
    expect(message.content).to eq("⛔#{I18n.t('conversations.messages.deleted')}")
    expect(message.content_attributes['deleted_for_everyone']).to be(true)
    expect(message.content_attributes['deleted_source']).to eq('whatsapp_remote')
    expect(message.content_attributes['deleted_at']).to be_present
    expect(message.content_attributes['link_preview']).to eq('url' => 'https://example.com')
  end

  it 'marks an incoming message as deleted when the contact revokes it for everyone' do
    message = create(
      :message,
      inbox: inbox,
      account: inbox.account,
      message_type: :incoming,
      source_id: 'CONTACT-DELETE-1',
      content: 'Mensagem recebida'
    )

    service.send(
      :update_message_with_status,
      message,
      { status: 'deleted', timestamp: Time.current.to_i }.with_indifferent_access
    )

    message.reload
    expect(message.deleted).to be(true)
    expect(message.content_attributes['deleted_for_everyone']).to be(true)
    expect(message.content_attributes['deleted_source']).to eq('whatsapp_remote')
  end

  it 'keeps remote deletion idempotent' do
    message = create(
      :message,
      inbox: inbox,
      account: inbox.account,
      message_type: :incoming,
      source_id: 'CONTACT-DELETE-2',
      content: 'Mensagem recebida',
      content_attributes: { deleted: true, deleted_at: 1.minute.ago.utc.iso8601 }
    )

    expect(message).not_to receive(:update!)
    service.send(
      :update_message_with_status,
      message,
      { status: 'deleted', timestamp: Time.current.to_i }.with_indifferent_access
    )
  end
end
