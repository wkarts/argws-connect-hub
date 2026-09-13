Rails.application.config.to_prepare do
  User.include TwoFactorAuthenticatable unless User < TwoFactorAuthenticatable
end

Rails.application.routes.append do
  devise_scope :user do
    post '/frontend_auth/sign_in', to: 'frontend_auth/sessions#create'
    post '/frontend_auth/two_factor/verify', to: 'frontend_auth/sessions#verify_two_factor'

    get '/frontend_auth/two_factor/settings', to: 'frontend_auth/two_factor_authentication#show'
    post '/frontend_auth/two_factor/settings', to: 'frontend_auth/two_factor_authentication#create'
    post '/frontend_auth/two_factor/settings/confirm', to: 'frontend_auth/two_factor_authentication#confirm'
    post '/frontend_auth/two_factor/settings/recovery_codes', to: 'frontend_auth/two_factor_authentication#recovery_codes'
    delete '/frontend_auth/two_factor/settings', to: 'frontend_auth/two_factor_authentication#destroy'
  end
end
