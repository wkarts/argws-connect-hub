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
    it 'creates the first administrator through AccountBuilder' do
      builder = instance_double(AccountBuilder, perform: true)
      allow(AccountBuilder).to receive(:new).and_return(builder)
      allow(RestClient).to receive(:post)

      post :create, params: {
        user: {
          name: 'HUB Admin',
          company: 'HUB',
          email: 'admin@example.com',
          password: 'Password123!'
        }
      }

      expect(AccountBuilder).to have_received(:new).with(
        account_name: 'HUB',
        user_full_name: 'HUB Admin',
        email: 'admin@example.com',
        user_password: 'Password123!',
        super_admin: true,
        confirmed: true
      )
      expect(builder).to have_received(:perform)
      expect(RestClient).not_to have_received(:post)
      expect(response).to redirect_to('/')
    end

    it 'keeps the user on onboarding when AccountBuilder rejects the setup' do
      builder = instance_double(AccountBuilder)
      allow(builder).to receive(:perform).and_raise(StandardError, 'Invalid setup')
      allow(AccountBuilder).to receive(:new).and_return(builder)

      post :create, params: {
        user: {
          name: 'HUB Admin',
          company: 'HUB',
          email: 'admin@example.com',
          password: 'invalid'
        }
      }

      expect(response).to redirect_to('/installation/onboarding')
      expect(flash[:error]).to eq('Invalid setup')
    end

    it 'does not allow a second installation administrator to be created' do
      create(:user)
      allow(AccountBuilder).to receive(:new)

      post :create, params: {
        user: {
          name: 'Another Admin',
          company: 'Another Company',
          email: 'another@example.com',
          password: 'Password123!'
        }
      }

      expect(response).to redirect_to('/')
      expect(AccountBuilder).not_to have_received(:new)
    end
  end
end
