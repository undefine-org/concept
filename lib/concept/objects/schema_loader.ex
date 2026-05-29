defmodule Concept.Objects.SchemaLoader do
  @moduledoc """
  Loads a workspace's object-type schema bundles for the `ToolProjector` and
  the MCP schema-introspection resource. System-actor reads (cross-cutting,
  read-only) scoped to one tenant.
  """
  require Ash.Query

  alias Concept.Objects.{ObjectType, FieldDef, WorkflowState, Transition}

  @system %{system?: true}

  @doc """
  Return `[%{object_type, field_defs, workflow_states, transitions}]` for a
  workspace — everything the projector needs to synthesize typed tools.
  """
  def bundles(workspace_id) do
    workspace_id
    |> object_types()
    |> Enum.map(&bundle(&1, workspace_id))
  end

  @doc "Load one bundle for a specific object type id (nil if not found)."
  def bundle_for(object_type_id, workspace_id) do
    case Ash.get(ObjectType, object_type_id,
           tenant: workspace_id,
           actor: @system,
           authorize?: false
         ) do
      {:ok, type} -> bundle(type, workspace_id)
      _ -> nil
    end
  end

  defp object_types(workspace_id) do
    ObjectType
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
  end

  defp bundle(type, workspace_id) do
    %{
      object_type: type,
      field_defs: field_defs(type.id, workspace_id),
      workflow_states: workflow_states(type.workflow_id, workspace_id),
      transitions: transitions(type.workflow_id, workspace_id)
    }
  end

  defp field_defs(type_id, workspace_id) do
    FieldDef
    |> Ash.Query.filter(object_type_id == ^type_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
  end

  defp workflow_states(nil, _workspace_id), do: []

  defp workflow_states(workflow_id, workspace_id) do
    WorkflowState
    |> Ash.Query.filter(workflow_id == ^workflow_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
  end

  defp transitions(nil, _workspace_id), do: []

  defp transitions(workflow_id, workspace_id) do
    Transition
    |> Ash.Query.filter(workflow_id == ^workflow_id)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
  end
end
