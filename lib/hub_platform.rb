# frozen_string_literal: true

# HUB local installation metadata. No remote registration or usage reporting is performed here.
class HubPlatform
  def self.installation_identifier
    identifier = InstallationConfig.find_by(name: 'INSTALLATION_IDENTIFIER')&.value
    identifier ||= InstallationConfig.create!(name: 'INSTALLATION_IDENTIFIER', value: SecureRandom.uuid).value
    identifier
  end

  def self.billing_url = ''
  def self.pricing_plan = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value || 'community'
  def self.pricing_plan_quantity = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')&.value || 100_000
  def self.support_config = { support_website_token: nil, support_script_url: nil, support_identifier_hash: nil }
end
