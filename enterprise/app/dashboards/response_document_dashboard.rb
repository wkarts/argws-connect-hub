require 'administrate/base_dashboard'

class ResponseDocumentDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    account: Field::BelongsToSearch.with_options(class_name: 'Account', searchable_field: [:name, :id], order: 'id DESC'),
    content: Field::Text.with_options(searchable: true),
    document_id: Field::Number,
    document_link: Field::String.with_options(searchable: true),
    document_type: Field::String,
    response_source: Field::BelongsToSearch.with_options(class_name: 'ResponseSource', searchable_field: [:name, :id, :source_link], order: 'id DESC'),
    responses: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id account response_source document_link].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id account response_source document_link document_id document_type content created_at updated_at responses].freeze
  FORM_ATTRIBUTES = %i[account response_source document_link document_id document_type content].freeze
  COLLECTION_FILTERS = {
    account: ->(resources, attr) { resources.where(account_id: attr) },
    response_source: ->(resources, attr) { resources.where(response_source_id: attr) }
  }.freeze

  def display_resource(response_document)
    "Document: ##{response_document.id} - #{response_document.document_link}"
  end
end
