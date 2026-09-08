# frozen_string_literal: true

# HUB local platform compatibility facade.
# No registration, usage metrics, billing, analytics, support widget or push payloads
# are transmitted to an external vendor service.
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
  def self.instance_config = { installation_identifier: installation_identifier, installation_version: Hub.config[:version] }
  def self.instance_metrics = {}
  def self.sync_with_hub = nil
  def self.register_instance(*) = nil
  def self.send_push(*) = nil
  def self.emit_event(*) = nil
end
