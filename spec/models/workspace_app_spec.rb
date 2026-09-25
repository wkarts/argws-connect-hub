require 'rails_helper'

RSpec.describe WorkspaceApp do
  let(:account) { create(:account) }
  let(:app) { described_class.new(account: account, name: 'Test application', url: 'https://app.example.test/home') }

  it 'starts as an empty manual catalog' do
    expect(account.workspace_apps).to be_empty
    expect(app).to be_valid
    expect(app.allow_saved_credentials).to be false
    expect(app.allow_auto_login).to be false
  end

  %w[javascript:alert(1) http://app.example.test data:text/html,test https://user:secret@app.example.test //app.example.test].each do |url|
    it "rejects an unsafe application URL: #{url}" do
      app.url = url
      expect(app).not_to be_valid
    end
  end

  it 'rejects embedding the HUB origin' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', '').and_return('https://hub.example.test')
    app.url = 'https://hub.example.test/app'
    expect(app).not_to be_valid
  end

  it 'requires a same-origin login destination' do
    app.assign_attributes(auth_mode: 'form_post', login_url: 'https://other.example.test/login')
    expect(app).not_to be_valid
    app.login_url = 'https://app.example.test/login'
    expect(app).to be_valid
  end

  it 'rejects unsafe, duplicate, method-override and CSRF fields' do
    app.assign_attributes(auth_mode: 'form_post', login_url: 'https://app.example.test/login')
    ['password', '_method', 'authenticity_token', 'submit', '<input>'].each do |field|
      app.username_field = field
      expect(app).not_to be_valid
    end
    app.username_field = 'user[email]'
    app.password_field = 'user[password]'
    expect(app).to be_valid
  end

  it 'does not enable password storage for ordinary login or automatic login without storage' do
    app.allow_saved_credentials = true
    expect(app).not_to be_valid
    app.assign_attributes(auth_mode: 'form_post', login_url: 'https://app.example.test/login', allow_saved_credentials: false, allow_auto_login: true)
    expect(app).not_to be_valid
  end

  it 'rejects unknown users and IDs from another company' do
    outsider = create(:user)
    app.allowed_user_ids = [outsider.id]
    expect(app).not_to be_valid
  end

  it 'restricts selected access while allowing company administrators' do
    agent = create(:user, account: account, role: :agent)
    admin = create(:user, account: account, role: :administrator)
    app.assign_attributes(access_mode: 'selected', allowed_user_ids: [agent.id])
    expect(app).to be_valid
    expect(app.accessible_to?(account.account_users.find_by(user: agent))).to be true
    expect(app.accessible_to?(account.account_users.find_by(user: admin))).to be true
    expect(app.accessible_to?(create(:account_user))).to be false
  end

  it 'permits raster icons and rejects SVG' do
    app.icon.attach(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" />'), filename: 'icon.svg', content_type: 'image/svg+xml')
    expect(app).not_to be_valid
    expect(app.errors[:icon]).to be_present
  end

  it 'rejects images over 1 MB' do
    app.icon.attach(io: StringIO.new('x' * (1.megabyte + 1)), filename: 'icon.png', content_type: 'image/png', identify: false)
    expect(app).not_to be_valid
    expect(app.errors[:icon]).to include('must not exceed 1 MB')
  end
end
