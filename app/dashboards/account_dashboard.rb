require 'administrate/base_dashboard'

class AccountDashboard < Administrate::BaseDashboard
  enterprise_attribute_types = if HubApp.enterprise?
                                 {
                                   limits: Enterprise::AccountLimitsField,
                                   all_features: Enterprise::AccountFeaturesField
                                 }
                               else
                                 {}
                               end

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    users: CountField,
    conversations: CountField,
    locale: Field::Select.with_options(collection: LanguageConfig.enabled_codes),
    status: Field::Select.with_options(collection: [['Ativa', 'active'], ['Suspensa', 'suspended']]),
    account_users: Field::HasMany
  }.merge(enterprise_attribute_types).freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    locale
    users
    conversations
    status
  ].freeze

  enterprise_show_page_attributes = HubApp.enterprise? ? %i[limits all_features] : []
  SHOW_PAGE_ATTRIBUTES = (%i[
    id
    name
    created_at
    updated_at
    locale
    status
    conversations
    account_users
  ] + enterprise_show_page_attributes).freeze

  enterprise_form_attributes = HubApp.enterprise? ? %i[limits all_features] : []
  FORM_ATTRIBUTES = (%i[
    name
    locale
    status
  ] + enterprise_form_attributes).freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(account)
    "##{account.id} #{account.name}"
  end

  def permitted_attributes(action)
    super + [limits: {}]
  end
end
