defmodule Concept.Knowledge.Community do
  @moduledoc "Community detection + LLM summarization on top of the structural graph."

  require Logger

  @doc """
  Runs community detection (Leiden clustering) + LLM summarization for a workspace.

  ## Returns
  - `{:ok, %{communities_detected: N, summaries_written: M}}`
  - `{:error, reason}`
  """
  def rebuild_communities(workspace_id) do
    collection_name = Concept.Knowledge.Config.collection_for(workspace_id)
    llm_model = Concept.Knowledge.Config.llm_model()

    with {:ok, detect_result} <-
           Arcana.Maintenance.detect_communities(Concept.Repo,
             collection: collection_name,
             levels: 2
           ),
         {:ok, summarize_result} <-
           Arcana.Maintenance.summarize_communities(Concept.Repo,
             collection: collection_name,
             llm: llm_model
           ) do
      communities_detected = Map.get(detect_result, :communities_detected, 0)
      summaries_written = Map.get(summarize_result, :summaries_written, 0)

      Logger.info("Communities rebuilt",
        workspace_id: workspace_id,
        communities: communities_detected,
        summaries: summaries_written
      )

      {:ok, %{communities_detected: communities_detected, summaries_written: summaries_written}}
    end
  end
end