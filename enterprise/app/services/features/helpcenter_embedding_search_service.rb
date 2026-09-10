class Features::HelpcenterEmbeddingSearchService < Features::BaseService
  def enable_in_installation
    create_tables
  end

  def disable_in_installation
    drop_tables
  end

  def feature_enabled?
    vector_extension_enabled? && MIGRATION_VERSION.table_exists?(:article_embeddings)
  end

  def create_tables
    return unless vector_extension_enabled?

    create_article_embeddings_table
  end

  def drop_tables
    MIGRATION_VERSION.drop_table :article_embeddings if MIGRATION_VERSION.table_exists?(:article_embeddings)
  end

  private

  def create_article_embeddings_table
    return if MIGRATION_VERSION.table_exists?(:article_embeddings)

    MIGRATION_VERSION.create_table :article_embeddings do |t|
      t.bigint :article_id, null: false
      t.text :term, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end
    MIGRATION_VERSION.add_index :article_embeddings, :embedding, using: :ivfflat, opclass: :vector_l2_ops
  end
end
