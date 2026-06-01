defmodule Concept.Knowledge.Indexer do
  @moduledoc """
  Single entrypoint for ingesting a Concept block-tree *source* (page or
  message) into Arcana for RAG retrieval.

  Centralizes the Arcana mechanics both ingest callers used to duplicate
  (`IngestPage` worker, `IngestionJob.PerformIngest`) and works around two
  Arcana 2.0.0 limitations that, together, silently disabled grounding:

  1. **Dropped chunker options.** `Arcana.Ingest.ingest/2` whitelists only
     `[:chunk_size, :chunk_overlap, :format, :size_unit]` from its opts; a
     `:chunker_opts` key is discarded. Chunker options must instead ride on a
     per-call `:chunker` override (`{module, opts}`), which Arcana merges into
     the chunker's defaults. Without this, `BlockChunker` received `[]` and
     raised `KeyError` on every ingest — documents stuck in `:processing`,
     zero chunks, zero retrieval.

  2. **Dropped chunk metadata.** `Arcana.Ingest.embed_single_chunk/5` persists
     each chunk's text + embedding but NOT its `:metadata`. `BlockChunker`
     emits per-chunk `block_id`/`page_id`/`breadcrumbs` that citations require
     (`Respond.persist_citations/3` filters out hits lacking `block_id` AND
     `page_id`). We backfill that metadata after a successful ingest by
     re-running the (pure) chunker and matching on the stable `chunk_index`.

  Returns `{:ok, chunk_count}` or `{:error, reason}` (the raw Arcana error, so
  callers can classify rate-limit/timeout shapes).
  """
  import Ecto.Query

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
        backfill_chunk_metadata(result, chunker_opts)
        {:ok, chunk_count(result)}

      {:error, _reason} = err ->
        err
    end
  end

  # Real Arcana returns the persisted `%Arcana.Document{}`; recompute the
  # chunker output (pure) and stamp each chunk row's metadata by chunk_index.
  defp backfill_chunk_metadata(%Arcana.Document{id: document_id}, chunker_opts) do
    BlockChunker.chunk(nil, chunker_opts)
    |> Enum.each(fn %{chunk_index: idx, metadata: meta} ->
      from(c in "arcana_chunks",
        where: c.document_id == type(^document_id, :binary_id) and c.chunk_index == ^idx
      )
      |> Concept.Repo.update_all(set: [metadata: meta])
    end)
  end

  # Test mocks return a bare `%{chunks: n}` map (no document, no rows to
  # backfill) — nothing to do.
  defp backfill_chunk_metadata(_other, _chunker_opts), do: :ok

  defp chunk_count(%Arcana.Document{chunk_count: n}) when is_integer(n), do: n
  defp chunk_count(%{chunk_count: n}) when is_integer(n), do: n
  defp chunk_count(%{chunks: n}) when is_integer(n), do: n
  defp chunk_count(_), do: 0
end
