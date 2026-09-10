require 'rails_helper'

RSpec.describe 'Super Admin', type: :request do
  describe '/super_admin' do
    it 'renders the login page in pt-BR' do
      with_modified_env LOGRAGE_ENABLED: 'true' do
        get '/super_admin/sign_in'
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Bem-vindo à Administração')
        expect(response.body).to include('E-mail')
      end
    end

    it 'authenticates case-insensitive email and redirects to the admin root' do
      super_admin = create(:super_admin, password: 'Password123!', password_confirmation: 'Password123!')

      post '/super_admin/sign_in', params: {
        super_admin: {
          email: super_admin.email.upcase,
          password: 'Password123!'
        }
      }

      expect(response).to redirect_to(super_admin_root_path)
    end
  end
end
