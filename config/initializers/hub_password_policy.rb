# frozen_string_literal: true

Rails.application.configure do
  config.x[:hub] ||= ActiveSupport::HashWithIndifferentAccess.new
  config.x[:hub][:password_policy] ||= ActiveSupport::HashWithIndifferentAccess.new

  policy = config.x[:hub][:password_policy]
  policy[:uppercase] = ENV.fetch('HUB_PASSWORD_REQUIRED_UPPERCASE', '1').to_i
  policy[:lowercase] = ENV.fetch('HUB_PASSWORD_REQUIRED_LOWERCASE', '1').to_i
  policy[:number] = ENV.fetch('HUB_PASSWORD_REQUIRED_NUMBER', '1').to_i
  policy[:special] = ENV.fetch('HUB_PASSWORD_REQUIRED_SPECIAL', '1').to_i
end
