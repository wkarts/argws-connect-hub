require 'rails_helper'

RSpec.describe 'Super Admin Instance status', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/instance_status' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/instance_status'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      it 'shows the localized instance status page with the current HUB version' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/instance_status'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Versão do HUB')
        expect(response.body).to include(Hub.version)
        expect(response.body).to include(GIT_HASH)
      end
    end
  end
end
