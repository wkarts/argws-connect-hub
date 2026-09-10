# frozen_string_literal: true

# Metadados locais da instalação HUB. Nenhum registro remoto, cobrança ou
# telemetria é necessário para determinar a edição da aplicação.
class HubPlatform
  ENTERPRISE_PLAN = 'enterprise'
  ENTERPRISE_QUANTITY = HubApp.max_limit

  def self.installation_identifier
    identifier = InstallationConfig.find_by(name: 'INSTALLATION_IDENTIFIER')&.value
    identifier ||= InstallationConfig.create!(name: 'INSTALLATION_IDENTIFIER', value: SecureRandom.uuid).value
    identifier
  end

  def self.billing_url = ''
  def self.pricing_plan = ENTERPRISE_PLAN
  def self.pricing_plan_quantity = ENTERPRISE_QUANTITY
  def self.support_config = { support_website_token: nil, support_script_url: nil, support_identifier_hash: nil }
end
