require 'rails_helper'

RSpec.describe Installation::OnboardingController, type: :controller do
  describe 'POST #create' do
    it 'does not perform any remote registration after onboarding' do
      allow(AccountBuilder).to receive(:new).and_call_original
      allow(::Redis::Alfred).to receive(:delete)

      expect(HubPlatform).not_to respond_to(:register_instance)
    end
  end
end
