class Response < ApplicationRecord
  belongs_to :response_document, optional: true
  belongs_to :account
  belongs_to :response_source
  has_neighbors :embedding, normalize: true

  before_save :update_response_embedding
  before_validation :ensure_account

  enum status: { pending: 0, active: 1 }

  def self.search(query)
    embedding = Openai::EmbeddingsService.new.get_embedding(query)
    nearest_neighbors(:embedding, embedding, distance: 'cosine').first(5)
  end

  private

  def ensure_account
    self.account = response_source.account
  end

  def update_response_embedding
    self.embedding = Openai::EmbeddingsService.new.get_embedding("#{question}: #{answer}")
  end
end
