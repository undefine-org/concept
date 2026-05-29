defmodule Concept.Objects.Record.Changes.SyncTitle do
  @moduledoc """
  Keep the denormalized `Record.title` in sync with the value of the type's
  designated title field (`FieldDef.is_title?`) whenever `fields` changes.

  `title` is denormalized onto the record for cheap list/board display
  (avoiding a JSONB read per card). On create it is derived by
  `AssignDefaults`; on `update_fields` this change re-derives it so the board
  heading never drifts from the edited field value.
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      tenant = cs.tenant || Ash.Changeset.get_attribute(cs, :workspace_id)
      type_id = Ash.Changeset.get_attribute(cs, :object_type_id)
      fields = Ash.Changeset.get_attribute(cs, :fields) || %{}

      with false <- is_nil(tenant) or is_nil(type_id),
           %{key: key} <- title_def(type_id, tenant),
           title when is_binary(title) <- Map.get(fields, key) do
        Ash.Changeset.force_change_attribute(cs, :title, title)
      else
        _ -> cs
      end
    end)
  end

  defp title_def(type_id, tenant) do
    Concept.Objects.FieldDef
    |> Ash.Query.filter(object_type_id == ^type_id and is_title? == true)
    |> Ash.Query.set_tenant(tenant)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end
end
