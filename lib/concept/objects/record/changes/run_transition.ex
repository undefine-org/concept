defmodule Concept.Objects.Record.Changes.RunTransition do
  @moduledoc """
  Move a record to a new workflow state, enforcing the transition's guards.

  Engine steps (before_action):
    1. Resolve the `Transition` row `from = record.state_id → to = to_state_id`
       in the record's workflow. No such transition → reject.
       (When the record has no current state, allow entering the workflow's
       initial state.)
    2. Run every guard on the transition via the `Guards` registry, collecting
       all failures and reporting them together.
    3. On success, set `state_id` to the target.

  Mirrors the gate pattern of `Block.Changes.RequireOwnLock`: one before_action
  change owns the rule; the resource stays declarative.
  """
  use Ash.Resource.Change
  require Ash.Query

  alias Concept.Objects.{Guards, Transition, WorkflowState}

  @impl true
  def change(changeset, _opts, ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      to_state_id = Ash.Changeset.get_argument(cs, :to_state_id)
      to_name = Ash.Changeset.get_argument(cs, :to)
      record = cs.data
      tenant = cs.tenant || record.workspace_id
      actor = ctx.actor

      with {:ok, to_state} <- resolve_target(to_state_id, to_name, record, tenant),
           {:ok, transition} <- resolve(record, to_state, tenant),
           :ok <- run_guards(transition, record, to_state, actor, tenant) do
        Ash.Changeset.force_change_attribute(cs, :state_id, to_state.id)
      else
        {:error, msg} -> Ash.Changeset.add_error(cs, field: :state_id, message: msg)
      end
    end)
  end

  # Resolve the target state from either a state id or a state name. Name
  # resolution is scoped to the record's own workflow (so agents can speak
  # workflow vocabulary — "Done" — instead of opaque uuids), mirroring how the
  # id path stays available for the UI and the generic MCP spine.
  defp resolve_target(nil, nil, _record, _tenant),
    do: {:error, "provide to_state_id or to (state name)"}

  defp resolve_target(id, _name, _record, tenant) when is_binary(id),
    do: fetch_state(id, tenant)

  defp resolve_target(_id, name, record, tenant) when is_binary(name) do
    case workflow_id_for(record, tenant) do
      wid when is_binary(wid) ->
        WorkflowState
        |> Ash.Query.filter(workflow_id == ^wid and name == ^name)
        |> Ash.Query.set_tenant(tenant)
        |> Ash.read(authorize?: false)
        |> case do
          {:ok, [state | _]} -> {:ok, state}
          _ -> {:error, "no state named #{inspect(name)} in this workflow"}
        end

      _ ->
        {:error, "record has no workflow"}
    end
  end

  defp fetch_state(nil, _tenant), do: {:error, "to_state_id is required"}

  defp fetch_state(id, tenant) do
    case Ash.get(WorkflowState, id, tenant: tenant, authorize?: false) do
      {:ok, state} -> {:ok, state}
      _ -> {:error, "target state not found"}
    end
  end

  # No current state: allow entering an initial state of the record's OWN
  # workflow only (else a record could jump into another workflow's initial
  # state in the same tenant — a graph escape).
  defp resolve(%{state_id: nil} = record, to_state, tenant) do
    if to_state.is_initial? and to_state.workflow_id == workflow_id_for(record, tenant) do
      {:ok, %Transition{guards: []}}
    else
      {:error, "record has no state; can only enter its workflow's initial state"}
    end
  end

  defp resolve(%{state_id: from_id} = record, to_state, tenant) do
    wid = workflow_id_for(record, tenant)

    Transition
    |> Ash.Query.filter(
      workflow_id == ^wid and from_state_id == ^from_id and to_state_id == ^to_state.id
    )
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [t | _]} -> {:ok, t}
      _ -> {:error, "no transition from current state to #{to_state.name}"}
    end
  end

  # The record's workflow is its object type's workflow.
  defp workflow_id_for(%{object_type: %{workflow_id: wid}}, _tenant) when is_binary(wid), do: wid

  defp workflow_id_for(record, tenant) do
    case Ash.get(Concept.Objects.ObjectType, record.object_type_id,
           tenant: tenant,
           authorize?: false
         ) do
      {:ok, %{workflow_id: wid}} -> wid
      _ -> nil
    end
  end

  defp run_guards(%{guards: guards}, record, to_state, actor, tenant) when is_list(guards) do
    ctx = %{record: record, actor: actor, to_state: to_state, tenant: tenant}

    errors =
      guards
      |> Enum.map(fn spec ->
        kind = spec["kind"] || spec[:kind]
        config = spec["config"] || spec[:config] || %{}

        case Guards.lookup(kind) do
          {:ok, mod} -> mod.check(record, config, ctx)
          _ -> {:error, "unknown guard: #{kind}"}
        end
      end)
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, m} -> m end)

    case errors do
      [] -> :ok
      msgs -> {:error, Enum.join(msgs, "; ")}
    end
  end

  defp run_guards(_, _, _, _, _), do: :ok
end
