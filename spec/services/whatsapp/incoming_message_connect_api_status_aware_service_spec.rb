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
end
