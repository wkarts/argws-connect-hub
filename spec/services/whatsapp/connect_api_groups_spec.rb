require 'rails_helper'

RSpec.describe 'Connect API WhatsApp groups' do
  let(:group_jid) { '120363000000000001@g.us' }
  let(:participant) { '5575988881111@s.whatsapp.net' }
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', sync_templates: false, validate_provider_config: false,
           provider_config: { 'instance_name' => 'group-fixture', 'api_key' => 'fixture-key',
                              'phone_number_id' => '5575999992222', 'ignore_group_messages' => false })
  end
  let(:receiver) { Whatsapp::IncomingMessageConnectApiReliableService }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_BASE_URL', anything).and_return('https://connect.example.test')
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_AUTH_TOKEN', anything).and_return('fixture-installation-key')
    allow(Channels::Whatsapp::ConnectApiProfilePictureJob).to receive(:perform_later)
    allow(HubDiagnostics::Recorder).to receive(:emit)
  end

  def envelope(id: 'GROUP-1', from_me: false, sender: participant, subject: 'Equipe', jid: group_jid, kind: 'text')
    message = { id: id, from: sender.split('@').first, timestamp: Time.current.to_i.to_s, type: kind,
                connect_api: { from_me: from_me, remote_jid: jid, participant: sender, recovered: true } }
    message[kind] = kind == 'text' ? { body: 'Mensagem do grupo' } : { id: id, caption: 'Legenda', mime_type: 'image/png' }
    { object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'messages', value: {
      metadata: { display_phone_number: channel.provider_config['phone_number_id'], phone_number_id: channel.provider_config['phone_number_id'] },
      contacts: [{ wa_id: sender.split('@').first, group_id: jid, group_subject: subject, profile: { name: 'Participante' } }],
      messages: [message]
    } }] }] }.with_indifferent_access
  end

  def ingest(**options)
    receiver.new(inbox: channel.inbox, params: envelope(**options)).perform
  end

  it 'keeps groups disabled when the setting is absent, true or a legacy provider' do
    [nil, true, 'true', '1'].each do |value|
      config = channel.provider_config.except('ignore_group_messages')
      config['ignore_group_messages'] = value unless value.nil?
      channel.update_column(:provider_config, config)
      expect(channel.groups_enabled?).to be false
      expect { ingest }.not_to change(Message, :count)
    end
    channel.provider = 'whatsapp_cloud'
    expect(channel.groups_enabled?).to be false
  end

  it 'keeps group identity, sender and source id separate and emits group metadata' do
    ingest
    message = Message.find_by!(inbox: channel.inbox, source_id: 'GROUP-1')
    conversation = message.conversation
    expect(conversation.contact_inbox.source_id).to eq(group_jid)
    expect(conversation.contact.name).to eq('Equipe')
    expect(conversation.contact.phone_number).to be_nil
    expect(message.sender.phone_number).to eq('+5575988881111')
    expect(message.sender_id).not_to eq(conversation.contact_id)
    expect(message.content).to eq('*Participante*: Mensagem do grupo')
    expect(message.content_attributes).to include('whatsapp_group' => true, 'group_jid' => group_jid, 'group_participant' => participant)
    expect(conversation.push_event_data[:is_group]).to be true
  end

  it 'does not assign another participant name or phone to the group on later messages' do
    ingest
    ingest(id: 'GROUP-2', sender: '5575998881111@s.whatsapp.net', subject: nil)
    expect(channel.inbox.conversations.count).to eq(1)
    expect(channel.inbox.conversations.first.contact.name).to eq('Equipe')
    expect(channel.inbox.conversations.first.contact.phone_number).to be_nil
    expect(channel.inbox.messages.map(&:sender_id).uniq.length).to eq(2)
  end

  it 'is idempotent and never echoes an outgoing physical-device message back to the provider' do
    ingest(from_me: true)
    expect { ingest(from_me: true) }.not_to change(Message, :count)
    message = channel.inbox.messages.last
    expect(message).to be_outgoing
    expect(message.sender).to be_nil
    expect(message.content_attributes['connect_api_external_outgoing']).to be true
    expect(HTTParty).not_to receive(:post)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
  end

  it 'supports LID-only participants without inventing a phone number' do
    ingest(sender: '3000001@lid')
    message = channel.inbox.messages.last
    expect(message.sender.phone_number).to be_nil
    expect(message.sender.identifier).to eq("whatsapp-participant:#{channel.inbox.id}:3000001@lid")
    expect(message.conversation.contact_inbox.source_id).to eq(group_jid)
  end

  it 'accepts native group metadata even when a contacts envelope is absent' do
    payload = envelope
    payload[:entry][0][:changes][0][:value].delete(:contacts)
    receiver.new(inbox: channel.inbox, params: payload).perform
    expect(channel.inbox.messages.last.conversation.contact_inbox.source_id).to eq(group_jid)
  end

  it 'does not turn malformed group JIDs into individual contacts' do
    expect { ingest(jid: 'invalid-120@g.us') }.not_to change(Contact, :count)
    expect(channel.inbox.messages.count).to eq(0)
  end

  it 'preserves group captions and sender when receiving media' do
    allow_any_instance_of(receiver).to receive(:download_attachment_file).and_return(nil)
    ingest(kind: 'image')
    expect(channel.inbox.messages.last.content).to eq('*Participante*: Legenda')
    expect(channel.inbox.messages.last.conversation).to be_whatsapp_group
  end

  it 'sends group text to the exact JID and blocks queued replies after disabling groups' do
    ingest
    conversation = channel.inbox.messages.last.conversation
    message = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, content: 'Resposta')
    stub_request(:post, 'https://connect.example.test/message/sendText/group-fixture')
      .with { |request| JSON.parse(request.body)['number'] == group_jid }
      .to_return(status: 200, body: { key: { id: 'GROUP-OUT' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    expect(message.reload.source_id).to eq('GROUP-OUT')
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => true))
    next_message = create(:message, account: channel.account, inbox: channel.inbox, conversation: Conversation.find(conversation.id), message_type: :outgoing, content: 'Não enviar')
    Whatsapp::SendOnWhatsappService.new(message: next_message).perform
    expect(next_message.reload).to be_failed
    expect(next_message.source_id).to be_nil
    expect(conversation.reload.can_reply?).to be false
  end

  it 'preserves the exact group JID in attachment payloads' do
    service = Whatsapp::Providers::ConnectApiService.new(whatsapp_channel: channel)
    attachment = double(file_type: 'image', download_url: 'https://files.example.test/photo.png', file: double(attached?: false))
    message = double(content: 'Foto', attachments: [attachment])
    payload, endpoint, = service.send(:native_attachment_payload, group_jid, message, attachment)
    expect(endpoint).to eq('sendMedia')
    expect(payload).to include(number: group_jid, caption: 'Foto')
  end

  it 'uses the group JID, never a participant alias, as revoke fallback' do
    ingest
    conversation = channel.inbox.messages.last.conversation
    message = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, source_id: 'REVOKE-GROUP')
    client = instance_double(ConnectApi::Client)
    allow(client).to receive(:request).with(:post, '/chat/findMessages/group-fixture', anything).and_return([])
    expect(client).to receive(:request).with(:delete, '/chat/deleteMessageForEveryone/group-fixture', body: { id: 'REVOKE-GROUP', fromMe: true, remoteJid: group_jid }, timeout: 20)
    expect(Whatsapp::ConnectApiMessageRevokeService.new(message: message, client: client).perform!).to be true
  end

  it 'historically imports opted-in groups without reopening, sending or duplicating messages' do
    record = { 'key' => { 'id' => 'GROUP-HISTORY', 'remoteJid' => group_jid, 'fromMe' => false, 'participant' => participant },
               'pushName' => 'Participante', 'groupSubject' => 'Histórico da equipe', 'message' => { 'conversation' => 'Anterior' }, 'messageTimestamp' => 1.day.ago.to_i }
    service = Whatsapp::ConnectApiHistoricalReconciliationService.new(channel: channel, client: instance_double(ConnectApi::Client))
    result = service.process(record)
    expect(result.result).to eq('created')
    expect(result.conversation).to be_resolved
    expect(result.conversation.contact_inbox.source_id).to eq(group_jid)
    expect(result.conversation.contact.phone_number).to be_nil
    expect(result.message.sender.phone_number).to eq('+5575988881111')
    expect { service.process(record) }.not_to change(Message, :count)
    expect(Channels::Whatsapp::ConnectApiProfilePictureJob).not_to have_received(:perform_later)
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => true))
    record['key']['id'] = 'GROUP-HISTORY-DISABLED'
    expect { service.process(record) }.not_to change(Message, :count)
  end

  it 'allows the existing lightweight recovery job to process opted-in group envelopes' do
    job = Channels::Whatsapp::ConnectApiMediaSyncJob.new
    job.instance_variable_set(:@channel, channel)
    expect(job.send(:ignored_jid?, group_jid)).to be false
    expect(job.send(:ignored_jid?, 'status@broadcast')).to be true
    expect(job.send(:ignored_jid?, 'not-a-group@g.us')).to be true
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => true))
    expect(job.send(:ignored_jid?, group_jid)).to be true
  end

  context 'provider settings synchronization' do
    let(:remote) { { 'rejectCall' => true, 'groupsIgnore' => true, 'alwaysOnline' => false, 'readMessages' => false,
                     'readStatus' => true, 'syncFullHistory' => true, 'msgCall' => 'Preservar', 'voipMaxConcurrentCalls' => 3 } }

    it 'changes only groupsIgnore, verifies the result and never recreates the instance' do
      client = instance_double(ConnectApi::Client)
      allow(ConnectApi::Client).to receive(:new).with(timeout: 10).and_return(client)
      expect(client).to receive(:request).with(:get, '/settings/find/group-fixture').ordered.and_return(remote)
      expect(client).to receive(:request).with(:post, '/settings/set/group-fixture', body: remote.merge('groupsIgnore' => false)).ordered
      expect(client).to receive(:request).with(:get, '/settings/find/group-fixture').ordered.and_return(remote.merge('groupsIgnore' => false))
      expect(Whatsapp::ConnectApiGroupSettingsService.new(channel).sync!).to be true
    end

    it 'uses the existing instance credential when changing an externally bound inbox' do
      channel.provider_config = { 'connect_api_binding_mode' => 'existing' }
      client = instance_double(ConnectApi::BoundInstanceClient)
      allow(ConnectApi::BoundInstanceClient).to receive(:new).with(api_key: 'fixture-key', timeout: 10).and_return(client)
      expect(client).to receive(:request).with(:get, '/settings/find/group-fixture').and_return(remote.merge('groupsIgnore' => false))
      expect(client).not_to receive(:request).with(:post, anything, anything)
      expect(Whatsapp::ConnectApiGroupSettingsService.new(channel).sync!).to be true
    end

    it 'refuses to overwrite settings if the server omitted existing options' do
      client = instance_double(ConnectApi::Client)
      allow(ConnectApi::Client).to receive(:new).and_return(client)
      allow(client).to receive(:request).with(:get, '/settings/find/group-fixture').and_return('groupsIgnore' => true)
      expect(client).not_to receive(:request).with(:post, anything, anything)
      expect { Whatsapp::ConnectApiGroupSettingsService.new(channel).sync! }.to raise_error(ConnectApi::Error)
    end

    it 'syncs only an explicit opt-in change, not every inbox refresh' do
      fresh = Channel::Whatsapp.find(channel.id)
      allow(fresh).to receive(:provider_service).and_return(double(validate_provider_config?: true))
      sync = instance_double(Whatsapp::ConnectApiGroupSettingsService, sync!: true)
      allow(Whatsapp::ConnectApiGroupSettingsService).to receive(:new).with(fresh).and_return(sync)
      expect(fresh.valid?).to be true
      expect(Whatsapp::ConnectApiGroupSettingsService).not_to have_received(:new)
      fresh.update!(provider_config: { 'ignore_group_messages' => true })
      expect(Whatsapp::ConnectApiGroupSettingsService).to have_received(:new).with(fresh).once
      expect(fresh.reload.groups_enabled?).to be false
    end
  end

  context 'conversation tab and account/inbox authorization' do
    let(:admin) { create(:user, account: channel.account, role: :administrator) }
    let(:agent) { create(:user, account: channel.account, role: :agent) }
    before { Current.account = channel.account; ingest }

    it 'filters groups and exposes counts without replacing the existing three tabs' do
      group_conversation = channel.inbox.conversations.first
      create(:conversation, account: channel.account, inbox: channel.inbox, status: :open)
      result = ConversationFinder.new(admin, assignee_type: 'groups').perform
      expect(result[:conversations].map(&:id)).to eq([group_conversation.id])
      expect(result[:count]).to include(group_count: 1, all_count: 2)
      expect(ConversationFinder.new(admin, assignee_type: 'all').perform[:conversations].size).to eq(2)
    end

    it 'never exposes a group to a non-member or from a disabled inbox' do
      expect(ConversationFinder.new(agent, assignee_type: 'groups').perform[:conversations]).to be_empty
      create(:inbox_member, inbox: channel.inbox, user: agent)
      expect(ConversationFinder.new(agent, assignee_type: 'groups').perform[:conversations].size).to eq(1)
      channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => true))
      expect(ConversationFinder.new(admin, assignee_type: 'groups').perform[:conversations]).to be_empty
      expect(channel.inbox.conversations.count).to eq(1) # No history deletion.
    end

    it 'applies status and inbox filters to the group list and its count' do
      channel.inbox.conversations.first.update!(status: :resolved)
      expect(ConversationFinder.new(admin, assignee_type: 'groups').perform[:count][:group_count]).to eq(0)
      expect(ConversationFinder.new(admin, assignee_type: 'groups', status: 'resolved', inbox_id: channel.inbox.id).perform[:count][:group_count]).to eq(1)
      expect(ConversationFinder.new(admin, assignee_type: 'groups', status: 'resolved', inbox_id: -1).perform[:count][:group_count]).to eq(0)
    end
  end
end
