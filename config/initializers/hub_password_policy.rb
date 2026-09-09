# frozen_string_literal: true

Rails.application.configure do
  config.x.hub.password_policy = ActiveSupport::OrderedOptions.new
  config.x.hub.password_policy.uppercase = ENV.fetch('HUB_PASSWORD_REQUIRED_UPPERCASE', '1').to_i
  config.x.hub.password_policy.lowercase = ENV.fetch('HUB_PASSWORD_REQUIRED_LOWERCASE', '1').to_i
  config.x.hub.password_policy.number = ENV.fetch('HUB_PASSWORD_REQUIRED_NUMBER', '1').to_i
  config.x.hub.password_policy.special = ENV.fetch('HUB_PASSWORD_REQUIRED_SPECIAL', '1').to_i
end
