require 'rails_helper'

describe MessageFinder do
  subject(:message_finder) { described_class.new(conversation, params) }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, email: nil) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: user, contact: contact)
  end

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    # this outgoing message creates 2 additional messages because of the email hook execution service
    create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation)
  end

  describe '#perform' do
    context 'with filter_internal_messages false' do
      let(:params) { { filter_internal_messages: false } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with filter_internal_messages true' do
      let(:params) { { filter_internal_messages: true } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 4
      end
    end

    context 'with before attribute' do
      let!(:outgoing) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
      let(:params) { { before: outgoing.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with after attribute' do
      let(:params) { { after: conversation.messages.first.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.first.id).to be conversation.messages.second.id
        expect(result.last.message_type).to eq 'outgoing'
      end
    end

    context 'with after and before attribute' do
      let(:params) do
        {
          after: conversation.messages.first.id,
          before: conversation.messages.last.id
        }
      end

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.last.id).to be conversation.messages[-2].id
      end
    end

    context 'with reconciled historical messages whose ids are newer than the timeline cursor' do
      it 'paginates before by created_at and id instead of insertion id' do
        cursor = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          created_at: 10.minutes.ago
        )
        imported_history = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          created_at: 2.hours.ago
        )

        expect(imported_history.id).to be > cursor.id

        result = described_class.new(conversation, before: cursor.id).perform

        expect(result.map(&:id)).to include(imported_history.id)
        expect(result.map { |message| [message.created_at, message.id] })
          .to eq(result.map { |message| [message.created_at, message.id] }.sort)
      end

      it 'paginates after by created_at even when an older imported record has a larger id' do
        cursor = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          created_at: 3.hours.ago
        )
        newer = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          created_at: 1.hour.ago
        )
        imported_older = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          created_at: 4.hours.ago
        )

        expect(imported_older.id).to be > newer.id

        result = described_class.new(conversation, after: cursor.id).perform

        expect(result.map(&:id)).to include(newer.id)
        expect(result.map(&:id)).not_to include(imported_older.id)
      end
    end
  end
end
