require 'administrate/base_dashboard'

class ResponseDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    account: Field::BelongsToSearch.with_options(class_name: 'Account', searchable_field: [:name, :id], order: 'id DESC'),
    response_source: Field::BelongsToSearch.with_options(class_name: 'ResponseSource', searchable_field: [:name, :id, :source_link], order: 'id DESC'),
    answer: Field::Text.with_options(searchable: true),
    question: Field::String.with_options(searchable: true),
    status: Field::Select.with_options(searchable: false, collection: lambda { |field| field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    response_document: Field::BelongsToSearch.with_options(class_name: 'ResponseDocument', searchable_field: [:document_link, :content, :id], order: 'id DESC'),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id question answer status response_document response_source account].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id status question answer response_document response_source account created_at updated_at].freeze
  FORM_ATTRIBUTES = %i[response_source response_document question answer status].freeze
  COLLECTION_FILTERS = {
    account: ->(resources, attr) { resources.where(account_id: attr) },
    response_source: ->(resources, attr) { resources.where(response_source_id: attr) },
    response_document: ->(resources, attr) { resources.where(response_document_id: attr) },
    status: ->(resources, attr) { resources.where(status: attr) }
  }.freeze

  def display_resource(response)
    "Response: ##{response.id} - #{response.question}"
  end
end
