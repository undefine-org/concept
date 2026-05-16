defmodule Concept.Knowledge.Config do
  @moduledoc "Central config helpers for the Knowledge domain."

  defmodule MissingApiKey do
    defexception message: "GOOGLE_API_KEY is not set; Concept.Knowledge cannot function."
  end

  @doc "Raises MissingApiKey if GOOGLE_API_KEY is not set."
  def api_key do
    System.get_env("GOOGLE_API_KEY") || raise MissingApiKey
  end

  @doc "Per-workspace Arcana collection name."
  def collection_for(workspace_id) when is_binary(workspace_id),
    do: "workspace:" <> workspace_id

  def llm_model, do: System.get_env("CONCEPT_LLM_MODEL", "google:gemini-2.5-flash")
  def embedder_dimensions, do: 768
end
