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
  Board view for the workspace's built-in Task type: states (ordered) +
  records grouped by their state's category. Returns
  `{:ok, %{type: ObjectType, states: [WorkflowState], columns: %{category => [Record]}}}`
  or `{:error, :no_task_type}`.

  Pure orchestration over code-interface fns so LiveViews stay query-free
  (Concept.Credo.Check.LiveViewPurity / EX9001).
  """
  def task_board(opts) do
    actor = Keyword.fetch!(opts, :actor)
    tenant = Keyword.fetch!(opts, :tenant)

    with {:ok, types} <- list_object_types(actor: actor, tenant: tenant),
         %{} = task <- Enum.find(types, &(&1.key == "task")) || {:error, :no_task_type},
         {:ok, states} <-
           list_workflow_states(task.workflow_id, actor: actor, tenant: tenant),
         {:ok, transitions} <-
           list_transitions(task.workflow_id, actor: actor, tenant: tenant),
         {:ok, field_defs} <- list_field_defs(task.id, actor: actor, tenant: tenant),
         {:ok, records} <- board_records(task.id, actor: actor, tenant: tenant) do
      states = Enum.sort_by(states, & &1.position)
      states_by_id = Map.new(states, &{&1.id, &1})
      initial = Enum.find(states, & &1.is_initial?)

      # Columns ARE the workflow's states (grouped by state id), so any
      # workflow renders correctly and empty categories don't force phantom
      # columns. Stateless records fall under the initial state.
      columns =
        Enum.group_by(records, fn r ->
          cond do
            is_map(r.state) and is_binary(Map.get(r.state, :id)) -> r.state.id
            initial -> initial.id
            true -> nil
          end
        end)

      {:ok,
       %{
         type: task,
         states: states,
         states_by_id: states_by_id,
         transitions: transitions,
         field_defs: field_defs,
         columns: columns
       }}
    else
      {:error, _} = err -> err
      _ -> {:error, :no_task_type}
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
end
