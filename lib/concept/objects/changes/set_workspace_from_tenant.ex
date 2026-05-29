defmodule Concept.Objects.Changes.SetWorkspaceFromTenant do
  @moduledoc """
  Set `workspace_id` from the action's tenant. With attribute multitenancy the
  tenant *is* the workspace id, so callers pass only `tenant:` — no redundant
  `workspace_id` argument. Falls back to an explicit `workspace_id` argument
  when present (e.g. tooling that sets it directly).
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    cond do
      is_binary(changeset.tenant) ->
        Ash.Changeset.force_change_attribute(changeset, :workspace_id, changeset.tenant)

      true ->
        case Ash.Changeset.get_argument(changeset, :workspace_id) do
          id when is_binary(id) ->
            Ash.Changeset.force_change_attribute(changeset, :workspace_id, id)

          _ ->
            changeset
        end
    end
  end
end
