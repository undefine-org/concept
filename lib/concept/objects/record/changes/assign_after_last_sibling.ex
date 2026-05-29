defmodule Concept.Objects.Record.Changes.AssignAfterLastSibling do
  @moduledoc "Compute default position as after-last-sibling within an object type."
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
        type_id = Ash.Changeset.get_attribute(changeset, :object_type_id)

        if is_nil(tenant) or is_nil(type_id) do
          changeset
        else
          assign_position(changeset, tenant, type_id)
        end
    end
  end

  defp assign_position(changeset, tenant, type_id) do
    last_pos =
      Concept.Objects.Record
      |> Ash.Query.filter(object_type_id == ^type_id)
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
