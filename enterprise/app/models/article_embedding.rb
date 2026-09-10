class ArticleEmbedding < ApplicationRecord
  belongs_to :article
  has_neighbors :embedding, normalize: true

  before_save :update_response_embedding

  private

  def update_response_embedding
    self.embedding = Openai::EmbeddingsService.new.get_embedding(term, 'text-embedding-3-small')
  end
end
