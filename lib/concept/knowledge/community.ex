defmodule Concept.Knowledge.Community do
  @moduledoc "Community detection + LLM summarization on top of the structural graph."

  alias Concept.Knowledge.Collections

  @doc """
  Runs community detection (Leiden clustering) + LLM summarization for a workspace.
  """
  def rebuild_communities(workspace_id) do
    collection = Collections.ensure_for_workspace(workspace_id)
    name = collection.name

    api_key = Concept.Knowledge.Config.api_key()
    llm_model = Concept.Knowledge.Config.llm_model()

    with {:ok, _} <- Arcana.GraphRAG.detect_communities(repo: Concept.Repo, collection: name),
         {:ok, _} <- Arcana.GraphRAG.summarize_communities(
           repo: Concept.Repo,
           collection: name,
           llm: {llm_model, api_key: api_key}
         ) do
      {:ok, %{}}
    end
  end
end
