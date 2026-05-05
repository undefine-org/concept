defmodule Concept.Knowledge.Search do
  @moduledoc "Hybrid search (vector + graph fusion) over workspace content."

  @doc """
  Performs hybrid search over a workspace's Arcana collection.
  Returns ranked chunks with text, score, and metadata.
  """
  def search(query, workspace_id, opts \\ []) do
    name = Concept.Knowledge.Config.collection_for(workspace_id)
    limit = Keyword.get(opts, :limit, 10)

    case Arcana.GraphRAG.fusion_search(query,
           repo: Concept.Repo,
           collection: name,
           limit: limit,
           mode: :hybrid
         ) do
      {:ok, results} -> {:ok, Enum.map(results, &serialize/1)}
      {:error, _reason} -> {:ok, []}
    end
  rescue
    _e in Ecto.NoResultsError -> {:ok, []}
    _e in FunctionClauseError -> {:ok, []}
  end

  defp serialize(chunk) do
    %{
      text: Map.get(chunk, :text) || Map.get(chunk, "text", ""),
      score: Map.get(chunk, :score) || Map.get(chunk, "score", 0.0),
      metadata: %{
        block_id: get_meta(chunk, "block_id"),
        page_id: get_meta(chunk, "page_id"),
        breadcrumbs: get_meta(chunk, "breadcrumbs"),
        block_type: get_meta(chunk, "block_type")
      }
    }
  end

  defp get_meta(chunk, key) do
    meta = Map.get(chunk, :metadata) || Map.get(chunk, "metadata", %{})
    Map.get(meta, key) || Map.get(meta, String.to_atom(key))
  end
end
