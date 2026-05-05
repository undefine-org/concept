defmodule Concept.Knowledge.Collections do
  @moduledoc "Collection lifecycle. Ensures a per-workspace Arcana collection exists."

  @doc """
  Ensures an Arcana collection exists for the given workspace.
  Idempotent — returns existing collection if one already exists.
  """
  def ensure_for_workspace(workspace_id) do
    name = Concept.Knowledge.Config.collection_for(workspace_id)
    Arcana.Collection.get_or_create(name, Concept.Repo, "Concept workspace #{workspace_id}")
  end
end
