defmodule Concept.Objects.WorkflowState.Changes.ClearSiblingInitials do
  @moduledoc """
  After marking a state as the workflow's initial state, clear `is_initial?`
  on every *other* state of the same workflow — a workflow has exactly one
  initial state. Without this, two states could both be `is_initial?`, making
  the record-seeding initial-state pick nondeterministic.
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.after_action(changeset, fn _cs, state ->
      tenant = state.workspace_id

      Concept.Objects.WorkflowState
      |> Ash.Query.filter(workflow_id == ^state.workflow_id and id != ^state.id)
      |> Ash.Query.filter(is_initial? == true)
      |> Ash.Query.set_tenant(tenant)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn sibling ->
        sibling
        |> Ash.Changeset.for_update(:update_state, %{
          name: sibling.name,
          category: sibling.category,
          is_initial?: false
        })
        |> Ash.update!(authorize?: false)
      end)

      {:ok, state}
    end)
  end
end
