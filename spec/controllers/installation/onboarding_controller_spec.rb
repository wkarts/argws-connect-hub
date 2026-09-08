require 'rails_helper'

RSpec.describe Installation::OnboardingController, type: :controller do
  describe 'POST #create' do
    it 'finishes onboarding without registering the installation with an external service' do
      builder = instance_double(AccountBuilder, perform: true)
      allow(AccountBuilder).to receive(:new).and_return(builder)
      allow(::Redis::Alfred).to receive(:get).and_return(true)
      allow(::Redis::Alfred).to receive(:delete)
      allow(RestClient).to receive(:post)

      post :create, params: {
        user: {
          name: 'HUB Admin',
          company: 'HUB',
          email: 'admin@example.com',
          password: 'Password123!'
        }
      }

      expect(builder).to have_received(:perform)
      expect(::Redis::Alfred).to have_received(:delete).with(::Redis::Alfred::HUB_INSTALLATION_ONBOARDING)
      expect(RestClient).not_to have_received(:post)
    end
  end
end
