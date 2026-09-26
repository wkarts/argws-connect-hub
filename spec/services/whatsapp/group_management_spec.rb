require 'rails_helper'
require_relative '../../support/whatsapp_group_management_helpers'

RSpec.describe 'WhatsApp group management domain' do
  include WhatsappGroupManagementHelpers
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', validate_provider_config: false, sync_templates: false,
           provider_config: { 'instance_name' => 'groups-test', 'phone_number_id' => '123456', 'ignore_group_messages' => false })
  end
  let(:group) { new_group }
  let(:admin) { create(:user, account: channel.account, role: :administrator) }
  let(:agent) { create(:user, account: channel.account) }
  let(:receiver) { Whatsapp::IncomingMessageConnectApiReliableService }

  before do
    allow(HubDiagnostics::Recorder).to receive(:emit)
    allow(Channels::Whatsapp::ConnectApiProfilePictureJob).to receive(:perform_later)
    Current.account = channel.account
  end
  after { Current.reset }

  it 'receives management messages without contacts, tickets, ticket messages or notifications' do
    payload = group_envelope(group)
    before = [Conversation.count, Message.count, Contact.count, Notification.count]
    receiver.new(inbox: channel.inbox, params: payload).perform
    expect([Conversation.count, Message.count, Contact.count, Notification.count]).to eq(before)
    saved = group.whatsapp_group_messages.sole
    expect(saved.content).to eq('Conteúdo protegido')
    expect(saved.sender_jid).to eq('30001@lid')
    expect(saved.user_id).to be_nil
    expect(group.whatsapp_group_deliveries.sole.treatment).to eq('management')
  end

  it 'also intercepts the status-aware webhook entry point, not only diagnostics' do
    expect { Whatsapp::IncomingMessageConnectApiStatusAwareService.new(inbox: channel.inbox, params: group_envelope(group)).perform }
      .to change(WhatsappGroupMessage, :count).by(1).and change(Conversation, :count).by(0)
  end

  it 'preserves Atendimento in the same inbox as an independent management group' do
    ticket_group = new_group(treatment: 'conversation', jid: '120363000000000088@g.us')
    receiver.new(inbox: channel.inbox, params: group_envelope(ticket_group, id: 'TICKET-ONE')).perform
    receiver.new(inbox: channel.inbox, params: group_envelope(group, id: 'MANAGEMENT-ONE')).perform
    expect(channel.inbox.conversations.count).to eq(1)
    expect(channel.inbox.messages.sole.source_id).to eq('TICKET-ONE')
    expect(group.whatsapp_group_messages.sole.source_id).to eq('MANAGEMENT-ONE')
  end

  it 'does not duplicate group deliveries after a mode change or a webhook retry' do
    payload = group_envelope(group, id: 'DEDUP-ONE')
    receiver.new(inbox: channel.inbox, params: payload).perform
    group.update_columns(treatment: 'conversation')
    expect { receiver.new(inbox: channel.inbox, params: payload).perform }
      .to change(WhatsappGroupMessage, :count).by(0).and change(Conversation, :count).by(0)
  end

  it 'updates and revokes the original management record after switching to Atendimento' do
    receiver.new(inbox: channel.inbox, params: group_envelope(group, id: 'STATUS-ONE', from_me: true)).perform
    group.update_columns(treatment: 'conversation')
    status = { id: 'STATUS-ONE', status: 'read' }.with_indifferent_access
    expect(Whatsapp::Groups::Status.consume(channel.inbox, status)).to be true
    expect(group.whatsapp_group_messages.sole.status).to eq('read')
    Whatsapp::Groups::Status.consume(channel.inbox, status.merge(status: 'sent'))
    expect(group.whatsapp_group_messages.sole.status).to eq('read')
    Whatsapp::Groups::Status.consume(channel.inbox, status.merge(status: 'deleted'))
    expect(group.whatsapp_group_messages.sole.content).to be_nil
    expect(group.whatsapp_group_messages.sole.deleted_at).to be_present
    expect(channel.inbox.conversations.count).to eq(0)
  end

  it 'ignores unselected groups without interpreting their JIDs as contacts' do
    WhatsappGroupSetting.for(channel.inbox).update!(selection_mode: 'selected')
    group.update!(selected: false)
    expect { receiver.new(inbox: channel.inbox, params: group_envelope(group)).perform }
      .to change(WhatsappGroupMessage, :count).by(0).and change(Conversation, :count).by(0)
  end

  it 'preserves events before a mode boundary for explicit reviewed history import' do
    group.update!(mode_changed_at: 1.minute.ago)
    value = group_value(group, timestamp: 1.hour.ago.to_i)
    router = Whatsapp::Groups::Router.new(channel.inbox)
    expect { router.dispatch(value) { raise 'Ticket path must not run' } }.to change(WhatsappGroupPendingEvent, :count).by(1)
    expect(group.whatsapp_group_messages.count).to eq(0)
    router.replay_pending!(group)
    expect(group.whatsapp_group_pending_events.count).to eq(0)
    expect(group.whatsapp_group_messages.sole.historical?).to be true
    expect(channel.inbox.conversations.count).to eq(0)
  end

  it 'imports native management history without ticket callbacks or outbound delivery' do
    raw = { 'key' => { 'id' => 'MANAGED-HISTORY', 'remoteJid' => group.jid, 'participant' => '30001@lid', 'fromMe' => false },
            'groupSubject' => group.name, 'message' => { 'conversation' => 'Histórico gerencial' }, 'messageTimestamp' => 1.day.ago.to_i }
    client = instance_double(ConnectApi::Client)
    result = Whatsapp::ConnectApiHistoricalReconciliationService.new(channel: channel, client: client).process(raw)
    expect(result.result).to eq('created')
    expect(result.conversation).to be_nil
    expect(group.whatsapp_group_messages.sole.historical?).to be true
    expect(channel.inbox.conversations.count).to eq(0)
  end

  it 'does not silently move an active ticket when changing treatment' do
    ticket_group = new_group(treatment: 'conversation')
    receiver.new(inbox: channel.inbox, params: group_envelope(ticket_group)).perform
    config = Whatsapp::Groups::Configuration.new(channel.inbox, admin)
    expect { config.update_group!(ticket_group, { 'lock_version' => ticket_group.reload.lock_version, 'treatment' => 'management' }, confirmed: true) }
      .to raise_error(Whatsapp::Groups::Configuration::Conflict)
    expect(ticket_group.reload.treatment).to eq('conversation')
    expect(ticket_group.conversations.sole).to be_open
  end

  it 'does not create a ticket when an administrator changes a management group to Atendimento' do
    config = Whatsapp::Groups::Configuration.new(channel.inbox, admin)
    expect { config.update_group!(group, { 'lock_version' => group.lock_version, 'treatment' => 'conversation' }, confirmed: true) }
      .not_to change(Conversation, :count)
    expect(group.reload.treatment).to eq('conversation')
    expect(group.whatsapp_group_policy_changes.sole.configuration['treatment']).to eq('conversation')
  end

  it 'checks assignment and message creation even outside the public controller' do
    ticket_group = new_group(treatment: 'conversation')
    receiver.new(inbox: channel.inbox, params: group_envelope(ticket_group)).perform
    conversation = ticket_group.conversations.sole
    ticket_group.update!(access_mode: 'selected', allowed_user_ids: [admin.id])
    expect(conversation.update(assignee: agent)).to be false
    ticket_group.update_columns(treatment: 'management')
    expect { create(:message, conversation: conversation, account: channel.account, inbox: channel.inbox) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'revalidates message recipients when realtime is delivered, including nested metadata envelopes' do
    ticket_group = new_group(treatment: 'conversation')
    receiver.new(inbox: channel.inbox, params: group_envelope(ticket_group)).perform
    message = channel.inbox.messages.sole
    create(:inbox_member, inbox: channel.inbox, user: agent)
    ticket_group.update!(access_mode: 'selected', allowed_user_ids: [agent.id])
    result = Whatsapp::Groups::BroadcastFilter.for([admin.pubsub_token, agent.pubsub_token], 'message.created', message.push_event_data.merge(account_id: channel.account_id))
    expect(result.map(&:first)).to eq([agent.pubsub_token])
    ticket_group.update!(allowed_user_ids: [])
    expect(Whatsapp::Groups::BroadcastFilter.for([agent.pubsub_token], 'message.created', message.push_event_data.merge(account_id: channel.account_id))).to be_empty
  end


  it 'passes ActionCable payload as a positional hash on Ruby 3' do
    message = group.whatsapp_group_messages.create!(
      direction: 'incoming', status: 'received', source_id: 'BROADCAST-RUBY3',
      content: 'Atualização', policy_version: group.policy_version, sent_at: Time.current
    )
    server = Class.new do
      attr_reader :calls
      def initialize
        @calls = []
      end
      def broadcast(stream, payload)
        @calls << [stream, payload]
      end
    end.new
    allow(ActionCable).to receive(:server).and_return(server)

    Whatsapp::Groups::BroadcastJob.perform_now(group.id, message.id)

    expect(server.calls.length).to eq(1)
    expect(server.calls.first.first).to eq(admin.pubsub_token)
    expect(server.calls.first.last).to include(event: 'whatsapp_group.changed')
    expect(server.calls.first.last[:data]).to include(group_id: group.id, message_id: message.id)
  end

  it 'mutes alerts without stopping ingestion or changing the group policy' do
    group.whatsapp_group_preferences.create!(user: admin, muted: true)
    receiver.new(inbox: channel.inbox, params: group_envelope(group)).perform
    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, hash_including(data: hash_including(notify: false)))
    Whatsapp::Groups::BroadcastJob.perform_now(group.id, group.whatsapp_group_messages.sole.id)
    expect(group.reload.treatment).to eq('management')
  end

  it 'uses a durable sending marker and refuses to automatically retry an uncertain delivery' do
    message = group.whatsapp_group_messages.create!(direction: 'outgoing', status: 'queued', user: admin, content: 'Saída', policy_version: group.policy_version, sent_at: Time.current)
    provider = instance_double(Whatsapp::Groups::Provider)
    allow(Whatsapp::Groups::Provider).to receive(:new).and_return(provider)
    expect(provider).to receive(:send!).once.and_raise(ConnectApi::Error, 'Acknowledgement lost')
    2.times { Whatsapp::Groups::SendJob.perform_now(message.id) }
    expect(message.reload.status).to eq('uncertain')
    expect(channel.inbox.conversations.count).to eq(0)
  end

  it 'does not resend a durable sending marker left by an interrupted process' do
    message = group.whatsapp_group_messages.create!(direction: 'outgoing', status: 'sending', user: admin, content: 'Saída', policy_version: group.policy_version, sent_at: Time.current)
    expect(Whatsapp::Groups::Provider).not_to receive(:new)
    Whatsapp::Groups::SendJob.perform_now(message.id)
    expect(message.reload.status).to eq('uncertain')
  end

  it 'rejects a queued send after the user loses access' do
    message = group.whatsapp_group_messages.create!(direction: 'outgoing', status: 'queued', user: admin, content: 'Saída', policy_version: group.policy_version, sent_at: Time.current)
    group.update!(access_mode: 'selected', allowed_user_ids: [])
    expect(Whatsapp::Groups::Provider).not_to receive(:new)
    Whatsapp::Groups::SendJob.perform_now(message.id)
    expect(message.reload.status).to eq('failed')
  end
  it 'does not create a ticket or personal contact from an unsupported group call' do
    group = new_group
    payload = { event: 'call', data: { action: 'incoming', call: { callId: 'GROUP-CALL', peerJid: group.jid, displayPeerJid: '5575988881111@s.whatsapp.net', isGroup: true } } }
    before = [Conversation.count, Message.count, Contact.count]
    Whatsapp::IncomingConnectApiCallService.new(channel: channel, params: payload).perform
    expect([Conversation.count, Message.count, Contact.count]).to eq(before)
  end

  it 'keeps a deleted history ledger as a tombstone rather than recreating tickets on replay' do
    group = new_group
    payload = group_envelope(group)
    receiver.new(inbox: channel.inbox, params: payload).perform
    message = group.whatsapp_group_messages.sole
    id = message.source_id
    message.destroy!
    expect(group.whatsapp_group_deliveries.find_by!(source_id: id).whatsapp_group_message_id).to be_nil
    expect { receiver.new(inbox: channel.inbox, params: payload).perform }.not_to change(WhatsappGroupMessage, :count)
    expect(channel.inbox.conversations.count).to eq(0)
  end

  it 'uses a source message identity scoped to each native group, not only the inbox' do
    first = new_group(treatment: 'conversation')
    second = new_group(jid: '120363000000000022@g.us', treatment: 'conversation')
    [first, second].each { |group| receiver.new(inbox: channel.inbox, params: group_envelope(group, id: 'SAME-SOURCE')).perform }
    expect(channel.inbox.messages.where(source_id: 'SAME-SOURCE').count).to eq(2)
    expect(first.conversations.count).to eq(1)
    expect(second.conversations.count).to eq(1)
  end

  it 'also isolates duplicate source IDs through the status-aware receiver' do
    first = new_group(treatment: 'conversation')
    second = new_group(jid: '120363000000000022@g.us', treatment: 'conversation')
    [first, second].each do |current|
      Whatsapp::IncomingMessageConnectApiStatusAwareService.new(inbox: channel.inbox,
        params: group_envelope(current, id: 'STATUS-AWARE-SAME-ID')).perform
    end
    expect(channel.inbox.messages.where(source_id: 'STATUS-AWARE-SAME-ID').count).to eq(2)
    expect(first.conversations.sole.messages.sole.source_id).to eq('STATUS-AWARE-SAME-ID')
    expect(second.conversations.sole.messages.sole.source_id).to eq('STATUS-AWARE-SAME-ID')
  end

  it 'does not apply an individual receipt to a managed group with the same source ID' do
    message = group.whatsapp_group_messages.create!(direction: 'outgoing', status: 'sent', source_id: 'RECEIPT-COLLISION',
      content: 'Texto', policy_version: group.policy_version, sent_at: Time.current)
    result = Whatsapp::Groups::Status.consume(channel.inbox,
      { id: message.source_id, status: 'read', recipient_id: '5575988881111@s.whatsapp.net' }.with_indifferent_access)
    expect(result).to be false
    expect(message.reload.status).to eq('sent')
  end

  it 'retains ambiguity instead of choosing a group when a receipt has no peer' do
    message = group.whatsapp_group_messages.create!(direction: 'outgoing', status: 'sent', source_id: 'RECEIPT-COLLISION',
      content: 'Texto', policy_version: group.policy_version, sent_at: Time.current)
    ticket_group = new_group(treatment: 'conversation', jid: '120363000000000022@g.us')
    receiver.new(inbox: channel.inbox, params: group_envelope(ticket_group, id: message.source_id)).perform
    expect { Whatsapp::Groups::Status.consume(channel.inbox, { id: message.source_id, status: 'read' }.with_indifferent_access) }
      .to raise_error(HubDiagnostics::SourceMessagePending)
    expect(message.reload.status).to eq('sent')
  end

  it 'rechecks media binding inside the group lock before using the provider' do
    message = group.whatsapp_group_messages.create!(direction: 'incoming', status: 'received', source_id: 'MEDIA-BINDING',
      kind: 'image', policy_version: group.policy_version, sent_at: Time.current)
    # Deterministic boundary injection; this is not a multi-process lock test.
    allow(Whatsapp::Groups::Lock).to receive(:with).and_wrap_original do |original, current, &block|
      channel.update_column(:provider_config, channel.provider_config.merge('instance_name' => 'different-instance'))
      original.call(current, &block)
    end
    expect(Whatsapp::Groups::Provider).not_to receive(:new)
    Whatsapp::Groups::MediaJob.perform_now(message.id)
    expect(message.reload.external_error).to include('instância da caixa mudou')
    expect(message.files).not_to be_attached
  end

end
