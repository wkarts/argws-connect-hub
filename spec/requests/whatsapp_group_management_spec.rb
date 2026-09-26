require 'rails_helper'
require_relative '../support/whatsapp_group_management_helpers'

RSpec.describe 'Group inbox administration and operational authorization', type: :request do
  include WhatsappGroupManagementHelpers
  let!(:channel) do
    create(:channel_whatsapp, provider: 'connectapi', validate_provider_config: false, sync_templates: false,
           provider_config: { 'instance_name' => 'groups-test', 'phone_number_id' => '123456', 'ignore_group_messages' => false })
  end
  let(:account) { channel.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:group) { new_group }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:settings_path) { "#{base}/inboxes/#{channel.inbox.id}/whatsapp_group_settings" }

  before do
    allow(HubDiagnostics::Recorder).to receive(:emit)
    allow(Channels::Whatsapp::ConnectApiProfilePictureJob).to receive(:perform_later)
  end

  def join_agent
    create(:inbox_member, inbox: channel.inbox, user: agent)
  end

  it 'routes every administrative action through the account and inbox IDs used by the settings tab' do
    [
      [:get, settings_path, 'show'],
      [:patch, settings_path, 'update'],
      [:post, "#{settings_path}/sync", 'sync'],
      [:patch, "#{settings_path}/bulk_update", 'bulk_update'],
      [:patch, "#{settings_path}/groups/123", 'update_group'],
      [:post, "#{settings_path}/groups/123/replay", 'replay']
    ].each do |method, path, action|
      recognized = Rails.application.routes.recognize_path(path, method: method)
      expect(recognized).to include(controller: 'api/v1/accounts/whatsapp_group_settings', action: action,
                                    account_id: account.id.to_s, inbox_id: channel.inbox.id.to_s)
      expect(recognized[:group_id]).to eq('123') if path.include?('/groups/123')
    end
  end

  it 'uses native administrator permission for reading and writing configuration' do
    join_agent
    get settings_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch settings_path, headers: agent.create_new_auth_token, params: { settings: { selection_mode: 'all', lock_version: 0 } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get settings_path, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['settings']['default_treatment']).to eq('conversation')
  end

  it 'does not resolve settings belonging to another account' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/inboxes/#{channel.inbox.id}/whatsapp_group_settings", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps administrator configuration access separate from restricted group content' do
    join_agent
    group.update!(access_mode: 'selected', allowed_user_ids: [agent.id])
    get settings_path, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/whatsapp_groups/#{group.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{base}/whatsapp_groups/#{group.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key('allowed_user_ids')
  end

  it 'rejects users outside the inbox and stale configuration revisions' do
    group
    patch "#{settings_path}/groups/#{group.id}", headers: admin.create_new_auth_token,
          params: { group: { lock_version: group.lock_version, access_mode: 'selected', allowed_user_ids: [agent.id] } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch "#{settings_path}/groups/#{group.id}", headers: admin.create_new_auth_token,
          params: { group: { lock_version: 999, treatment: 'conversation' }, confirmed: true }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'does not alter an existing group when changing defaults for newly discovered groups' do
    group
    settings = WhatsappGroupSetting.for(channel.inbox)
    patch settings_path, headers: admin.create_new_auth_token,
          params: { settings: { lock_version: settings.lock_version, selection_mode: 'selected', default_treatment: 'conversation' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(group.reload.treatment).to eq('management')
    discovered = WhatsappGroup.discover!(channel.inbox, '120363000000000077@g.us')
    expect(discovered.treatment).to eq('conversation')
    expect(discovered.selected?).to be false
  end

  it 'prevents double submit from creating two pending outgoing messages' do
    headers = admin.create_new_auth_token
    payload = { group_message: { client_id: SecureRandom.uuid, content: 'Mensagem de teste' } }
    2.times do
      post "#{base}/whatsapp_groups/#{group.id}/messages", headers: headers, params: payload, as: :json
      expect(response).to have_http_status(:created)
    end
    expect(group.whatsapp_group_messages.count).to eq(1)
    expect(account.conversations.count).to eq(0)
  end

  it 'protects direct management message reads from unauthorized users' do
    group.whatsapp_group_messages.create!(content: 'Segredo', direction: 'incoming', source_id: 'SECRET', sent_at: Time.current, policy_version: 1)
    get "#{base}/whatsapp_groups/#{group.id}/messages", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Segredo')
  end

  it 'adds group restrictions to legacy conversation routes and search' do
    join_agent
    ticket_group = new_group(treatment: 'conversation')
    Whatsapp::IncomingMessageConnectApiReliableService.new(inbox: channel.inbox, params: group_envelope(ticket_group)).perform
    conversation = ticket_group.conversations.sole
    ticket_group.update!(access_mode: 'selected', allowed_user_ids: [admin.id])
    get "#{base}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/conversations", headers: agent.create_new_auth_token, as: :json
    expect(response.body).not_to include('Conteúdo protegido')
  end

  it 'delivers files only through a currently authorized user session, with no public blob bypass' do
    message = group.whatsapp_group_messages.create!(content: 'Imagem', direction: 'incoming', source_id: 'FILE', kind: 'image', sent_at: Time.current, policy_version: 1)
    message.files.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png', content_type: 'image/png')
    path = Whatsapp::Groups::Presenter.message(message, admin)[:files].first[:url]
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(Whatsapp::Groups::StorageGuard.protected?(message.files.first.blob)).to be true
    get Rails.application.routes.url_helpers.rails_blob_path(message.files.first, only_path: true)
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps mute personal and does not grant administration to an agent' do
    join_agent
    patch "#{base}/whatsapp_groups/#{group.id}/preference", headers: agent.create_new_auth_token, params: { preference: { muted: true } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(group.whatsapp_group_preferences.find_by!(user: agent).muted?).to be true
    expect(group.reload.treatment).to eq('management')
  end
  it 'protects tracked thumbnails and preview descendants, not only the original blob' do
    message = group.whatsapp_group_messages.create!(direction: 'incoming', source_id: 'VARIANT-FILE', kind: 'image',
      sent_at: Time.current, policy_version: 1)
    message.files.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'original.png', content_type: 'image/png')
    original = message.files.first.blob
    # Build the actual variant association without requiring image transformation.
    record = ActiveStorage::VariantRecord.create!(blob: original, variation_digest: SecureRandom.hex(20))
    record.image.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'derived.png', content_type: 'image/png')
    derivative = record.image.blob
    expect(Whatsapp::Groups::StorageGuard.protected?(derivative)).to be true
    get Rails.application.routes.url_helpers.rails_blob_path(derivative, only_path: true)
    expect(response).to have_http_status(:not_found)
    variant_key = "variants/#{original.key}/#{'a' * 64}"
    expect(Whatsapp::Groups::StorageGuard.source_for_key(variant_key)).to eq(original)
  end

  it 'serves an authorized single byte range without a full blob download' do
    message = group.whatsapp_group_messages.create!(direction: 'incoming', source_id: 'RANGE-FILE', kind: 'document',
      sent_at: Time.current, policy_version: 1)
    message.files.attach(io: StringIO.new('abcdefghij'), filename: 'test.txt', content_type: 'text/plain')
    path = Whatsapp::Groups::Presenter.message(message, admin)[:files].first[:url]
    expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download)
    get path, headers: admin.create_new_auth_token.merge('Range' => 'bytes=2-4')
    expect(response).to have_http_status(:partial_content)
    expect(response.body).to eq('cde')
    expect(response.headers['Content-Range']).to eq('bytes 2-4/10')
  end

end
