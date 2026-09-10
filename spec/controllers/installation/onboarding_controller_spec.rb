require 'rails_helper'

RSpec.describe Installation::OnboardingController, type: :controller do
  describe 'GET #index' do
    it 'allows onboarding for a fresh installation without requiring Redis state' do
      get :index

      expect(response).to have_http_status(:success)
    end

    it 'closes onboarding when the installation already has a user' do
      create(:user)

      get :index

      expect(response).to redirect_to('/')
    end
  end

  describe 'POST #create' do
    it 'creates and authenticates the first administrator through AccountBuilder' do
      super_admin = build_stubbed(:super_admin)
      account = build_stubbed(:account)
      builder = instance_double(AccountBuilder, perform: [super_admin, account])
      allow(AccountBuilder).to receive(:new).and_return(builder)
      allow(controller).to receive(:sign_in)

      post :create, params: {
        user: {
          name: 'Administrador HUB',
          company: 'HUB',
          email: 'admin@example.com',
          password: 'Password123!'
        }
      }

      expect(AccountBuilder).to have_received(:new).with(
        account_name: 'HUB',
        user_full_name: 'Administrador HUB',
        email: 'admin@example.com',
        user_password: 'Password123!',
        super_admin: true,
        confirmed: true
      )
      expect(controller).to have_received(:sign_in).with(:super_admin, super_admin)
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'keeps the user on onboarding when AccountBuilder rejects the setup' do
      builder = instance_double(AccountBuilder)
      allow(builder).to receive(:perform).and_raise(StandardError, 'Configuração inválida')
      allow(AccountBuilder).to receive(:new).and_return(builder)

      post :create, params: {
        user: {
          name: 'Administrador HUB',
          company: 'HUB',
          email: 'admin@example.com',
          password: 'invalid'
        }
      }

      expect(response).to redirect_to('/installation/onboarding')
      expect(flash[:error]).to eq('Configuração inválida')
    end

    it 'does not allow a second installation administrator to be created' do
      create(:user)
      allow(AccountBuilder).to receive(:new)

      post :create, params: {
        user: {
          name: 'Outro administrador',
          company: 'Outra empresa',
          email: 'outro@example.com',
          password: 'Password123!'
        }
      }

      expect(response).to redirect_to('/')
      expect(AccountBuilder).not_to have_received(:new)
    end
  end
end
