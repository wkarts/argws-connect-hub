# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboxPolicy, type: :policy do
  subject(:inbox_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:administrator_context) do
    {
      user: administrator,
      account: account,
      account_user: account.account_users.find_by!(user_id: administrator.id)
    }
  end
  let(:agent_context) do
    {
      user: agent,
      account: account,
      account_user: account.account_users.find_by!(user_id: agent.id)
    }
  end

  permissions :create?, :destroy?, :update?, :set_agent_bot? do
    context 'when administrator' do
      it { expect(inbox_policy).to permit(administrator_context, inbox) }
    end

    context 'when agent' do
      it { expect(inbox_policy).not_to permit(agent_context, inbox) }
    end
  end

  permissions :index? do
    context 'when administrator' do
      it { expect(inbox_policy).to permit(administrator_context, inbox) }
    end

    context 'when agent' do
      it { expect(inbox_policy).to permit(agent_context, inbox) }
    end
  end

  permissions :show? do
    let(:assigned_inbox) { create(:inbox, account: account, name: 'Assigned') }
    let(:unassigned_inbox) { create(:inbox, account: account, name: 'Unassigned') }

    before do
      create(:inbox_member, user: agent, inbox: assigned_inbox)
    end

    it 'allows an administrator to see every inbox in the account' do
      expect(inbox_policy).to permit(administrator_context, unassigned_inbox)
    end

    it 'allows an agent to see an assigned inbox' do
      expect(inbox_policy).to permit(agent_context, assigned_inbox)
    end

    it 'does not allow an agent to see an unassigned inbox' do
      expect(inbox_policy).not_to permit(agent_context, unassigned_inbox)
    end
  end

  describe InboxPolicy::Scope do
    let!(:assigned_inbox) { create(:inbox, account: account, name: 'Assigned') }
    let!(:unassigned_inbox) { create(:inbox, account: account, name: 'Unassigned') }
    let(:scope) { account.inboxes }

    before do
      create(:inbox_member, user: agent, inbox: assigned_inbox)
    end

    it 'returns only assigned inboxes for an agent' do
      resolved = described_class.new(agent_context, scope).resolve

      expect(resolved).to contain_exactly(assigned_inbox)
      expect(resolved).not_to include(unassigned_inbox)
    end

    it 'returns every account inbox for an administrator' do
      resolved = described_class.new(administrator_context, scope).resolve

      expect(resolved).to include(assigned_inbox, unassigned_inbox)
    end
  end
end
