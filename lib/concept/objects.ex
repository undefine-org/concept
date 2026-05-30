defmodule Concept.Objects do
  @moduledoc """
  The Objects domain: a runtime database builder.

  Workspaces define their own object *types* (`ObjectType`), *fields*
  (`FieldDef`), and *workflows* (`Workflow`/`WorkflowState`/`Transition`);
  rows are `Record`s with a validated JSONB field-bag and `RecordLink` edges.

  **Task** is the first built-in type — seeded per workspace — not a special
  resource. See `docs/objects_and_tasks.md`.
  """
  use Ash.Domain,
    otp_app: :concept,
    extensions: [AshAdmin.Domain, AshAi, Concept.AutoTools]

  admin do
    show? true
  end

  resources do
    resource Concept.Objects.ObjectType do
      define :create_object_type, action: :create, args: [:name]
      define :rename_object_type, args: [:name], action: :rename
      define :set_object_type_workflow, action: :set_workflow, args: [:workflow_id]
      define :list_object_types, action: :list
      define :get_object_type, action: :read, get_by: :id
    end

    resource Concept.Objects.FieldDef do
      define :create_field_def, action: :create, args: [:object_type_id, :name, :field_type]
      define :update_field_def, args: [:name, :required?, :config], action: :update_def
      define :reorder_field_def, args: [:position], action: :reorder
      define :list_field_defs, args: [:object_type_id], action: :list_for_type
    end

    resource Concept.Objects.Record do
      define :create_record, action: :create, args: [:object_type_id]
      define :update_record_fields, args: [:fields], action: :update_fields
      define :transition_record, args: [:to_state_id], action: :transition
      define :assign_record, args: [:assignee_id], action: :assign
      define :reorder_record, args: [:position], action: :reorder
      define :archive_record, action: :archive
      define :list_records, args: [:object_type_id], action: :list_for_type
      define :ready_records, args: [:object_type_id], action: :ready
      define :all_ready_records, action: :ready_all
      define :board_records, args: [:object_type_id], action: :board
      define :my_records, action: :mine
      define :get_record, action: :read, get_by: :id
    end

    resource Concept.Objects.RecordLink do
      define :link_records, args: [:from_record_id, :to_record_id, :field_def_id], action: :create
      define :unlink_records, action: :destroy
      define :list_links_from, args: [:from_record_id], action: :from_record
    end

    resource Concept.Objects.Workflow do
      define :create_workflow, action: :create, args: [:name]
      define :rename_workflow, action: :rename, args: [:name]
      define :list_workflows, action: :list
      define :get_workflow, action: :read, get_by: :id
    end

    resource Concept.Objects.WorkflowState do
      define :create_workflow_state, action: :create, args: [:workflow_id, :name, :category]
      define :update_workflow_state, action: :update_state, args: [:name, :category]
      define :mark_workflow_state_initial, action: :mark_initial
      define :reorder_workflow_state, action: :reorder, args: [:position]
      define :list_workflow_states, action: :list_for_workflow, args: [:workflow_id]
      define :get_workflow_state, action: :read, get_by: :id
    end

    resource Concept.Objects.Transition do
      define :create_transition,
        action: :create,
        args: [:workflow_id, :from_state_id, :to_state_id]

      define :set_transition_guards, action: :set_guards, args: [:guards]
      define :list_transitions, action: :list_for_workflow, args: [:workflow_id]
      define :transitions_from_state, action: :from_state, args: [:from_state_id]
    end
  end

  @doc """
  Create a **usable** object type (default workflow + title field) and return
  it — the human "Create type" path. Unlike the bare `create_object_type/1`
  primitive, a scaffolded type is immediately functional on a board and via
  the `create_<type>` MCP tool. Single source of truth:
  `Concept.Objects.Scaffold` (shared with the Task `Seeder`).
  """
  def scaffold_object_type(name, opts) do
    Concept.Objects.Scaffold.object_type(name, opts)
  end

  @doc """
  Board view for **any** object type: states (ordered) + records grouped by
  state id, with the preloaded transition graph and field defs. Returns
  `{:ok, %{type, states, states_by_id, transitions, field_defs, columns,
  blocked_ids}}` or `{:error, reason}`.

  The generic projection behind every type's board; `task_board/1` is the
  built-in Task instance of it. Pure orchestration over code-interface fns so
  LiveViews stay query-free (EX9001 / LiveViewPurity).
  """
  def object_board(type_id, opts) do
    actor = Keyword.fetch!(opts, :actor)
    tenant = Keyword.fetch!(opts, :tenant)

    with {:ok, type} <- get_object_type(type_id, actor: actor, tenant: tenant) do
      build_board(type, actor, tenant)
    end
  end

  @doc """
  Board view for the workspace's built-in Task type — the seeded instance of
  `object_board/2`. Same shape, or `{:error, :no_task_type}` when absent.

  Pure orchestration over code-interface fns so LiveViews stay query-free
  (Concept.Credo.Check.LiveViewPurity / EX9001).
  """
  def task_board(opts) do
    actor = Keyword.fetch!(opts, :actor)
    tenant = Keyword.fetch!(opts, :tenant)

    with {:ok, types} <- list_object_types(actor: actor, tenant: tenant),
         %{} = task <- Enum.find(types, &(&1.key == "task")) || {:error, :no_task_type} do
      build_board(task, actor, tenant)
    else
      {:error, _} = err -> err
      _ -> {:error, :no_task_type}
    end
  end

  # Shared board builder: load a resolved type's workflow graph, fields, and
  # records, then group records into columns keyed by state id so any workflow
  # renders correctly (empty categories don't force phantom columns; stateless
  # records fall under the initial state).
  defp build_board(type, actor, tenant) do
    with {:ok, states} <-
           list_workflow_states(type.workflow_id, actor: actor, tenant: tenant),
         {:ok, transitions} <-
           list_transitions(type.workflow_id, actor: actor, tenant: tenant),
         {:ok, field_defs} <- list_field_defs(type.id, actor: actor, tenant: tenant),
         {:ok, records} <- board_records(type.id, actor: actor, tenant: tenant) do
      states = Enum.sort_by(states, & &1.position)
      states_by_id = Map.new(states, &{&1.id, &1})
      initial = Enum.find(states, & &1.is_initial?)

      columns =
        Enum.group_by(records, fn r ->
          cond do
            is_map(r.state) and is_binary(Map.get(r.state, :id)) -> r.state.id
            initial -> initial.id
            true -> nil
          end
        end)

      blocked_ids = Concept.Objects.Record.Blocking.blocked_ids(records, tenant)

      {:ok,
       %{
         type: type,
         states: states,
         states_by_id: states_by_id,
         transitions: transitions,
         field_defs: field_defs,
         columns: columns,
         blocked_ids: blocked_ids
       }}
    end
  end

  @doc """
  Available moves for a record computed *purely* over a preloaded board graph
  (`board.transitions` + `board.states_by_id`) — no per-card queries. Returns
  `[%{transition, to_state, requirements}]` where `requirements` are the
  human-legible guard descriptions (shown before the move is attempted).
  """
  def moves_for(record, %{transitions: transitions, states_by_id: by_id}) do
    transitions
    |> Enum.filter(&(&1.from_state_id == record.state_id))
    |> Enum.map(fn t ->
      case Map.get(by_id, t.to_state_id) do
        nil -> nil
        to_state -> %{transition: t, to_state: to_state, requirements: requirements(t)}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Human-legible descriptions of a transition's guards, via `Guard.describe/1`
  (delegated to the `Guards` registry). Reused by the board move affordance,
  the workflow editor, and MCP tool descriptions.
  """
  def requirements(%{guards: guards}) when is_list(guards),
    do: Concept.Objects.Guards.describe_all(guards)

  def requirements(_), do: []

  @doc """
  Pull-model "work" view for a member: what is assigned to me, and what is
  ready for anyone to pick up — across *every* object type in the workspace
  (not just Tasks). Returns

      {:ok, %{mine: [Record], ready: [Record], blocked_ids: MapSet.t()}}

  - `mine`   — records assigned to the actor (state + object_type loaded),
    newest-touched first.
  - `ready`  — unassigned, unblocked records in a `:todo`-category state
    (`Record.Blocking` is the single blocked? authority).
  - `blocked_ids` — ids among `mine` that have an incomplete `blocked_by`
    dependency, so the UI can badge them without a second pass.

  Pure orchestration over code-interface fns so the LiveView stays query-free
  (Concept.Credo.Check.LiveViewPurity / EX9001).
  """
  def work_view(opts) do
    actor = Keyword.fetch!(opts, :actor)
    tenant = Keyword.fetch!(opts, :tenant)

    with {:ok, mine} <- my_records(actor: actor, tenant: tenant),
         {:ok, ready} <- all_ready_records(actor: actor, tenant: tenant) do
      blocked_ids = Concept.Objects.Record.Blocking.blocked_ids(mine, tenant)
      {:ok, %{mine: mine, ready: ready, blocked_ids: blocked_ids}}
    end
  end
end
