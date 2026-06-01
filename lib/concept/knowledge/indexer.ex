defmodule Concept.Knowledge.Indexer do
  @moduledoc """
  Single entrypoint for ingesting a Concept block-tree *source* (page or
  message) into Arcana for RAG retrieval.

  Centralizes the Arcana mechanics both ingest callers used to duplicate
  (`IngestPage` worker, `IngestionJob.PerformIngest`).

  Chunker inputs (`:blocks`, `:page`/`:message_id`, `:workspace_id`,
  `:breadcrumbs`) are delivered to `BlockChunker` via Arcana's per-call
  `:chunker` override (`{module, opts}`), which Arcana merges into the
  chunker's defaults. (Arcana's `ingest/2` only whitelists generic chunk
  options like `:chunk_size`; a bare `:chunker_opts` key would be ignored.)

  Per-chunk metadata (`block_id`/`page_id`/`breadcrumbs`) that `BlockChunker`
  emits is persisted by Arcana and surfaced in search results by the vendored
  fork (undefine-org/arcana PRs #1 and #2), so citations can attribute hits to
  a source block/page with no Concept-side backfill.

  Returns `{:ok, chunk_count}` or `{:error, reason}` (the raw Arcana error, so
  callers can classify rate-limit/timeout shapes).
  """
  alias Concept.Knowledge.{BlockChunker, Config}

  @doc """
  Ingest a source's blocks. `chunker_opts` are the `BlockChunker` inputs
  (`:blocks` plus `:page`/`:message_id`/`:workspace_id`/`:breadcrumbs`).
  """
  def ingest_source(workspace_id, source_id, body, chunker_opts) do
    collection = Config.collection_for(workspace_id)
    arcana_module = Application.get_env(:concept, :arcana_module, Arcana)

    case arcana_module.ingest(body,
           repo: Concept.Repo,
           collection: collection,
           source_id: source_id,
           chunker: {BlockChunker, chunker_opts}
         ) do
      {:ok, result} ->
        {:ok, chunk_count(result)}

      {:error, _reason} = err ->
        err
    end
  end

  defp chunk_count(%Arcana.Document{chunk_count: n}) when is_integer(n), do: n
  defp chunk_count(%{chunk_count: n}) when is_integer(n), do: n
  defp chunk_count(%{chunks: n}) when is_integer(n), do: n
  defp chunk_count(_), do: 0
end
