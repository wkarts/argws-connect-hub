require 'administrate/base_dashboard'

class ResponseSourceDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    account: Field::BelongsToSearch.with_options(class_name: 'Account', searchable_field: [:name, :id], order: 'id DESC'),
    name: Field::String.with_options(searchable: true),
    response_documents: Field::HasMany,
    responses: Field::HasMany,
    source_link: Field::String.with_options(searchable: true),
    source_model_id: Field::Number,
    source_model_type: Field::String,
    source_type: Field::Select.with_options(searchable: false, collection: lambda { |field| field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name account source_link].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id name account source_link source_model_id source_model_type source_type created_at updated_at response_documents responses].freeze
  FORM_ATTRIBUTES = %i[account name source_link source_model_id source_model_type source_type].freeze
  COLLECTION_FILTERS = {
    account: ->(resources, attr) { resources.where(account_id: attr) }
  }.freeze

  def display_resource(response_source)
    "Source: ##{response_source.id} - #{response_source.name}"
  end
end
