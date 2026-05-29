defmodule Concept.Objects.RecordLink.Changes.ValidateSameWorkspace do
  @moduledoc """
  Reject a `RecordLink` whose endpoints (`from_record`, `to_record`, optional
  `field_def`) live in a different workspace than the link's tenant.

  Ash attribute-multitenancy scopes reads and the `workspace_id` attribute,
  but the raw FK attributes are global — without this guard a member of two
  workspaces could create a cross-tenant edge, corrupting the relation graph
  and `FilterReady` readiness (a foreign `blocked_by` resolves to an empty
  blocker set, falsely reporting a record ready). Mirrors the guard on
  `Concept.Knowledge.Link`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      ws = Ash.Changeset.get_attribute(cs, :workspace_id) || cs.tenant

      cs
      |> check(:from_record_id, Concept.Objects.Record, ws)
      |> check(:to_record_id, Concept.Objects.Record, ws)
      |> check(:field_def_id, Concept.Objects.FieldDef, ws)
    end)
  end

  defp check(cs, field, resource, ws) do
    case Ash.Changeset.get_attribute(cs, field) do
      nil ->
        cs

      id ->
        case Ash.get(resource, id, tenant: ws, authorize?: false) do
          {:ok, %{workspace_id: ^ws}} ->
            cs

          {:ok, _} ->
            Ash.Changeset.add_error(cs, field: field, message: "belongs to a different workspace")

          {:error, _} ->
            Ash.Changeset.add_error(cs, field: field, message: "does not exist in this workspace")
        end
    end
  end
end
