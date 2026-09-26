require 'rails_helper'

describe ConversationMuteHelpers do
  let!(:conversation) { create(:conversation) }
  let(:contact) { conversation.contact }

  before do
    contact.update!(blocked: false, additional_attributes: {})
    allow(conversation).to receive(:dispatch_conversation_updated_event)
  end

  it 'silences without blocking or resolving the contact conversation' do
    original_status = conversation.status

    conversation.mute!(duration_seconds: 1800)

    contact.reload
    expect(contact.blocked?).to be(false)
    expect(conversation.reload.status).to eq(original_status)
    expect(conversation.muted?).to be(true)
    expect(conversation.mute_expires_at).to be_present
    expect(contact.additional_attributes.dig('hub_mute', 'muted')).to be(true)
  end

  it 'supports permanent silence without changing blocked' do
    conversation.mute!(duration_seconds: 0)

    expect(contact.reload.blocked?).to be(false)
    expect(conversation.muted?).to be(true)
    expect(conversation.mute_expires_at).to be_nil
  end

  it 'rejects unsupported mute durations' do
    expect do
      conversation.mute!(duration_seconds: 300)
    end.to raise_error(ArgumentError, 'Período de silenciamento inválido.')
  end

  it 'removes HUB mute metadata without blocking side effects' do
    conversation.mute!(duration_seconds: 3600)
    conversation.unmute!

    expect(contact.reload.additional_attributes['hub_mute']).to be_nil
    expect(contact.blocked?).to be(false)
    expect(conversation.muted?).to be(false)
  end
end
