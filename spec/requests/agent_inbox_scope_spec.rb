require 'rails_helper'

RSpec.describe 'Agent inbox scope', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:assigned_inbox) { create(:inbox, account: account, name: 'Assigned inbox') }
  let!(:unassigned_inbox) { create(:inbox, account: account, name: 'Unassigned inbox') }

  before do
    create(:inbox_member, user: agent, inbox: assigned_inbox)
  end

  def inbox_ids_for(user)
    get "/api/v1/accounts/#{account.id}/inboxes",
        headers: user.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('payload').map { |inbox| inbox.fetch('id') }
  end

  it 'returns only assigned inboxes to an agent' do
    expect(inbox_ids_for(agent)).to contain_exactly(assigned_inbox.id)
  end

  it 'returns all account inboxes to an administrator' do
    expect(inbox_ids_for(admin)).to include(assigned_inbox.id, unassigned_inbox.id)
  end

  it 'does not allow an agent to open an unassigned inbox directly' do
    get "/api/v1/accounts/#{account.id}/inboxes/#{unassigned_inbox.id}",
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
