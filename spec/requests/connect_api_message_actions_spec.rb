require 'rails_helper'

RSpec.describe 'Connect|API message actions', type: :request do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'message-actions-instance',
        'api_key' => 'instance-token'
      }
    )
  end

  before do
    create(:inbox_member, inbox: channel.inbox, user: agent)
    channel.inbox.update!(allow_agent_to_delete_message: true)
  end

  describe 'DELETE message' do
    let(:contact) { create(:contact, account: account, phone_number: '+5575988111111') }
    let(:contact_inbox) do
      create(
        :contact_inbox,
        contact: contact,
        inbox: channel.inbox,
        source_id: '5575988111111'
      )
    end
    let(:conversation) do
      create(
        :conversation,
        account: account,
        inbox: channel.inbox,
        contact: contact,
        contact_inbox: contact_inbox
      )
    end
    let(:message) do
      create(
        :message,
        account: account,
        inbox: channel.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: false,
        source_id: 'REMOTE-DELETE-1',
        content: 'Mensagem para apagar'
      )
    end

    it 'revokes remotely before marking the HUB message as deleted' do
      revoke_service = instance_double(
        Whatsapp::ConnectApiMessageRevokeService,
        perform!: true
      )
      allow(Whatsapp::ConnectApiMessageRevokeService)
        .to receive(:new)
        .with(message: message)
        .and_return(revoke_service)

      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:ok)
      expect(revoke_service).to have_received(:perform!).once

      message.reload
      expect(message.deleted).to be(true)
      expect(message.content_attributes['deleted_for_everyone']).to be(true)
      expect(message.content_attributes['deleted_at']).to be_present
      expect(message.content).not_to eq('Mensagem para apagar')
    end

    it 'keeps the HUB message untouched when remote revoke is not confirmed' do
      revoke_service = instance_double(Whatsapp::ConnectApiMessageRevokeService)
      allow(revoke_service).to receive(:perform!).and_raise(
        Whatsapp::ConnectApiMessageRevokeService::Error,
        'O WhatsApp recusou a exclusão para todos. A mensagem foi mantida no HUB.'
      )
      allow(Whatsapp::ConnectApiMessageRevokeService)
        .to receive(:new)
        .with(message: message)
        .and_return(revoke_service)

      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('mantida no HUB')

      message.reload
      expect(message.deleted).not_to be(true)
      expect(message.content).to eq('Mensagem para apagar')
    end
  end

  describe 'POST forward' do
    let(:source_contact) { create(:contact, account: account, phone_number: '+5575988222222') }
    let(:source_contact_inbox) do
      create(
        :contact_inbox,
        contact: source_contact,
        inbox: channel.inbox,
        source_id: '5575988222222'
      )
    end
    let(:conversation) do
      create(
        :conversation,
        account: account,
        inbox: channel.inbox,
        contact: source_contact,
        contact_inbox: source_contact_inbox
      )
    end
    let(:message) do
      create(
        :message,
        account: account,
        inbox: channel.inbox,
        conversation: conversation,
        message_type: :incoming,
        content: 'Mensagem a encaminhar'
      )
    end

    it 'returns the created destination immediately when there is only one recipient' do
      target = create(:contact, account: account, phone_number: '+5575988333333')

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/forward",
           params: { contacts: [target.id] },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload['status']).to eq('forwarded')
      expect(payload['destination_count']).to eq(1)
      expect(payload['operation_id']).to be_present
      expect(payload.dig('destination', 'conversation_id')).to be_present
      expect(payload.dig('destination', 'message_id')).to be_present

      destination = account.conversations.find_by!(
        display_id: payload.dig('destination', 'conversation_id')
      )
      forwarded = destination.messages.find(payload.dig('destination', 'message_id'))

      expect(destination.contact_id).to eq(target.id)
      expect(forwarded.outgoing?).to be(true)
      expect(forwarded.content).to eq(message.content)
      expect(forwarded.additional_attributes).to include(
        'forwarded' => true,
        'forward_operation_id' => payload['operation_id'],
        'forwarded_from_message_id' => message.id,
        'forwarded_to_contact_id' => target.id
      )
    end

    it 'queues multiple recipients without selecting an arbitrary destination' do
      targets = [
        create(:contact, account: account, phone_number: '+5575988444444'),
        create(:contact, account: account, phone_number: '+5575988555555')
      ]
      message

      expect do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/forward",
             params: { contacts: targets.map(&:id) },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Conversations::ForwardMessageJob)

      expect(response).to have_http_status(:accepted)
      payload = response.parsed_body
      expect(payload['status']).to eq('queued')
      expect(payload['destination_count']).to eq(2)
      expect(payload['operation_id']).to be_present
      expect(payload['job_id']).to be_present
      expect(payload['destination']).to be_nil
    end

    it 'rejects a contact that belongs to another account' do
      foreign = create(:contact)

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/forward",
           params: { contacts: [foreign.id] },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('não pertence')
    end
  end
end
