require 'rails_helper'

RSpec.describe WorkspaceAppCredential do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:membership) { account.account_users.find_by(user: user) }
  let(:app) { account.workspace_apps.create!(name: 'Test application', url: 'https://app.example.test', auth_mode: 'form_post', login_url: 'https://app.example.test/login', allow_saved_credentials: true, allow_auto_login: true) }
  let(:credential) do
    record = app.workspace_app_credentials.new(account_user: membership)
    record.credentials = { 'username' => 'test-user', 'password' => 'not-a-real-password' }
    record.save!
    record
  end

  it 'encrypts credentials and decrypts only in the correct context' do
    expect(credential.encrypted_credentials).not_to include('test-user', 'not-a-real-password')
    expect(credential.reload.credentials).to eq('username' => 'test-user', 'password' => 'not-a-real-password')
    expect(WorkspaceApps::CredentialCipher.decrypt(credential.encrypted_credentials, purpose: 'wrong-context')).to be_nil
  end

  it 'does not accept a credential owned by another company' do
    other = create(:user, account: create(:account))
    credential.account_user = other.account_users.first
    expect(credential).not_to be_valid
  end

  it 'has one credential per application and company membership' do
    duplicate = credential.dup
    expect(duplicate).not_to be_valid
  end

  it 'invalidates the vault when the destination or login configuration changes' do
    credential
    app.update!(login_url: 'https://app.example.test/new-login')
    expect(app.workspace_app_credentials).to be_empty
  end

  it 'preserves credentials on cosmetic updates' do
    credential
    revision = app.integration_revision
    app.update!(name: 'Another label', icon_name: 'mail')
    expect(app.integration_revision).to eq(revision)
    expect(app.workspace_app_credentials.count).to eq(1)
  end

  it 'removes stored secrets when storage is disabled' do
    credential
    app.update!(allow_saved_credentials: false, allow_auto_login: false)
    expect(app.workspace_app_credentials).to be_empty
  end

  it 'revokes automatic login when the company disallows it' do
    credential.update!(auto_login: true)
    app.update!(allow_auto_login: false)
    expect(credential.reload.auto_login).to be false
  end

  it 'deletes secrets when the user membership is removed' do
    credential
    expect { membership.destroy! }.to change(described_class, :count).by(-1)
  end
end
