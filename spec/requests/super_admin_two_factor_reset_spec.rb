require 'rails_helper'

RSpec.describe 'Super Admin 2FA reset', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:user) { create(:user) }

  before do
    user.update!(
      two_factor_secret_ciphertext: 'ciphertext-secret',
      two_factor_pending_secret_ciphertext: 'ciphertext-pending',
      two_factor_enabled_at: Time.current,
      two_factor_last_counter: 321,
      two_factor_recovery_codes: ['recovery-code-digest']
    )
  end

  it 'does not reset 2FA without an authenticated super admin' do
    patch "/super_admin/users/#{user.id}", params: { reset_two_factor: true }

    expect(response).to have_http_status(:redirect)
    expect(user.reload.two_factor_secret_ciphertext).to eq('ciphertext-secret')
  end

  it 'invalidates the complete 2FA state for an authenticated super admin' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/users/#{user.id}", params: { reset_two_factor: true }

    expect(response).to redirect_to("http://www.example.com/super_admin/users/#{user.id}")

    user.reload
    expect(user.two_factor_secret_ciphertext).to be_nil
    expect(user.two_factor_pending_secret_ciphertext).to be_nil
    expect(user.two_factor_enabled_at).to be_nil
    expect(user.two_factor_last_counter).to be_nil
    expect(user.two_factor_recovery_codes).to eq([])
  end
end
