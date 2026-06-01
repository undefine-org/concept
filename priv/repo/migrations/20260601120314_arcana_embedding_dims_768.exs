defmodule Concept.Repo.Migrations.ArcanaEmbeddingDims768 do
  @moduledoc """
  Align Arcana embedding columns with the configured Gemini embedder.

  `arcana_chunks.embedding` and `arcana_graph_entities.embedding` were created
  as `vector(384)` (Arcana's default `bge-small` dimensionality). The app is
  configured with `Concept.Knowledge.GeminiEmbedder`, which emits **768**-dim
  vectors (Matryoshka-truncated from gemini-embedding-001). Inserts therefore
  failed with `expected 384 dimensions, not 768`, leaving every ingested
  document stuck in `:processing` with zero chunks — RAG retrieval silently
  returned no grounding.

  Zero chunks/entities exist at migration time, so the column type change is
  a clean rewrite. Stuck `:processing` documents (failed pre-fix ingests) are
  purged so the next reindex repopulates them cleanly.
  """
  use Ecto.Migration

  def up do
    # Drop the HNSW index (bound to the old column type), retype, recreate.
    execute "DROP INDEX IF EXISTS arcana_chunks_embedding_idx"

    alter table(:arcana_chunks) do
      modify :embedding, :vector, size: 768, null: false
    end

    execute """
    CREATE INDEX arcana_chunks_embedding_idx ON arcana_chunks
    USING hnsw (embedding vector_cosine_ops)
    """

    alter table(:arcana_graph_entities) do
      modify :embedding, :vector, size: 768
    end

    # Purge documents that never chunked under the broken pipeline. Chunks
    # cascade-delete via FK; a clean reindex will recreate them.
    execute "DELETE FROM arcana_documents WHERE status = 'processing'"
  end

  def down do
    execute "DROP INDEX IF EXISTS arcana_chunks_embedding_idx"

    alter table(:arcana_chunks) do
      modify :embedding, :vector, size: 384, null: false
    end

    execute """
    CREATE INDEX arcana_chunks_embedding_idx ON arcana_chunks
    USING hnsw (embedding vector_cosine_ops)
    """

    alter table(:arcana_graph_entities) do
      modify :embedding, :vector, size: 384
    end
  end
end
