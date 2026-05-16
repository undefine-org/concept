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

    search_opts = [
      repo: Concept.Repo,
      collections: [collection_name],
      mode: mode,
      limit: limit
    ]

    case Arcana.search(query, search_opts) do
      {:ok, results} ->
        hits = results |> Enum.with_index(1) |> Enum.map(&normalize_hit/1)
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

  defp normalize_hit({chunk, rank}) do
    metadata = Map.get(chunk, "metadata", %{})
    text = Map.get(chunk, "text", "")
    score = Map.get(chunk, "score", 0.0)
    chunk_id = Map.get(chunk, "id")

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