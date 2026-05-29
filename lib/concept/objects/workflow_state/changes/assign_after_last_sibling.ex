defmodule Concept.Objects.WorkflowState.Changes.AssignAfterLastSibling do
  @moduledoc "Compute default position as after-last-sibling within a workflow."
  use Ash.Resource.Change
  alias Concept.Pages.FractionalIndex
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :position) do
      pos when is_binary(pos) and pos != "" ->
        changeset

      _ ->
        tenant = changeset.tenant || Ash.Changeset.get_attribute(changeset, :workspace_id)
        workflow_id = Ash.Changeset.get_attribute(changeset, :workflow_id)

        if is_nil(tenant) or is_nil(workflow_id) do
          changeset
        else
          assign_position(changeset, tenant, workflow_id)
        end
    end
  end

  defp assign_position(changeset, tenant, workflow_id) do
    last_pos =
      Concept.Objects.WorkflowState
      |> Ash.Query.filter(workflow_id == ^workflow_id)
      |> Ash.Query.sort(position: :desc)
      |> Ash.Query.limit(1)
      |> Ash.Query.set_tenant(tenant)
      |> Ash.read!(authorize?: false)
      |> case do
        [%{position: p} | _] -> p
        _ -> nil
      end

    Ash.Changeset.force_change_attribute(
      changeset,
      :position,
      FractionalIndex.after_(last_pos)
    )
  end
end
