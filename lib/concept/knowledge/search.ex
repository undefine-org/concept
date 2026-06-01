defmodule Concept.Knowledge.Search do
  @moduledoc "Hybrid search (vector + graph fusion) over workspace content."

  require Logger

  @doc """
  Performs hybrid search over a workspace's Arcana collection.
  Returns ranked chunks with normalized metadata.

  ## Returns
  - `{:ok, [hit]}` where each hit is `%{block_id, page_id, breadcrumbs, snippet, score, rank, chunk_id}`
  - `{:error, reason}` on failure

  ## Options
  - `:mode` - `:hybrid` (default), `:semantic`, or `:keyword`
  - `:limit` - max results (default: 10)
  """
  def search(query, workspace_id, opts \\ []) do
    :telemetry.span(
      [:concept, :knowledge, :search],
      %{workspace_id: workspace_id},
      fn ->
        result = do_search(query, workspace_id, opts)
        {result, %{workspace_id: workspace_id}}
      end
    )
  end

  defp do_search(query, workspace_id, opts) do
    collection_name = Concept.Knowledge.Config.collection_for(workspace_id)
    mode = Keyword.get(opts, :mode, :hybrid)
    limit = Keyword.get(opts, :limit, 10)

    search_opts =
      [
        repo: Concept.Repo,
        collections: [collection_name],
        mode: mode,
        limit: limit
      ]
      # Forward an optional source filter (e.g. "page:<id>") so callers can
      # scope retrieval to a single page/subtree (BUG-053).
      |> maybe_put(:source_id, Keyword.get(opts, :source_id))

    case Arcana.search(query, search_opts) do
      {:ok, results} ->
        # Arcana 2.0's hybrid path rebuilds each hit from a fixed field set and
        # drops custom chunk metadata (block_id/page_id/breadcrumbs). Reload it
        # from the persisted chunk rows by id so citations can attribute hits
        # back to their source block/page.
        meta_by_id = load_chunk_metadata(results)

        hits =
          results
          |> Enum.with_index(1)
          |> Enum.map(fn {chunk, rank} -> normalize_hit({chunk, rank}, meta_by_id) end)

        {:ok, hits}

      {:error, reason} ->
        Logger.warning("Arcana search failed",
          workspace_id: workspace_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  rescue
    e in Ecto.NoResultsError ->
      Logger.debug("Collection not found for workspace #{workspace_id}", error: inspect(e))
      {:ok, []}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  # Load persisted chunk metadata keyed by chunk id, so hits can be enriched
  # regardless of which fields the active Arcana search mode preserves.
  defp load_chunk_metadata(results) do
    ids =
      results
      |> Enum.map(fn chunk -> Map.get(chunk, :id) || Map.get(chunk, "id") end)
      |> Enum.filter(&is_binary/1)

    case ids do
      [] ->
        %{}

      ids ->
        import Ecto.Query

        from(c in "arcana_chunks",
          where: c.id in ^Enum.map(ids, &Ecto.UUID.dump!/1),
          select: {c.id, c.metadata}
        )
        |> Concept.Repo.all()
        |> Map.new(fn {id, meta} -> {Ecto.UUID.load!(id), meta || %{}} end)
    end
  end

  defp normalize_hit({chunk, rank}, meta_by_id) do
    # Arcana returns chunks with atom keys
    chunk_id = Map.get(chunk, :id) || Map.get(chunk, "id")
    inline_meta = Map.get(chunk, :metadata) || Map.get(chunk, "metadata", %{})
    # Prefer DB-loaded metadata (authoritative); fall back to any inline map.
    metadata = Map.get(meta_by_id, chunk_id) || inline_meta || %{}
    text = Map.get(chunk, :text) || Map.get(chunk, "text", "")
    score = Map.get(chunk, :score) || Map.get(chunk, "score", 0.0)

    %{
      block_id: Map.get(metadata, "block_id"),
      page_id: Map.get(metadata, "page_id"),
      breadcrumbs: Map.get(metadata, "breadcrumbs"),
      snippet: text,
      score: score,
      rank: rank,
      chunk_id: chunk_id
    }
  end
end
