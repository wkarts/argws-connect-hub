class ResponseSource < ApplicationRecord
  enum source_type: { external: 0, kbase: 1, inbox: 2 }
  has_many :inbox_response_sources, dependent: :destroy_async
  has_many :inboxes, through: :inbox_response_sources
  belongs_to :account
  has_many :response_documents, dependent: :destroy_async
  has_many :responses, dependent: :destroy_async

  accepts_nested_attributes_for :response_documents

  def get_responses(query)
    embedding = Openai::EmbeddingsService.new.get_embedding(query)
    responses.active.nearest_neighbors(:embedding, embedding, distance: 'cosine').first(5)
  end
end
