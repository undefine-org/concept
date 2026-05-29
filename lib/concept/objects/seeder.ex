defmodule Concept.Objects.Seeder do
  @moduledoc """
  Seeds the built-in **Task** object type into a workspace: a default workflow
  (Backlog→Todo→Doing→Review→Done + Canceled), built-in fields (priority,
  blocked_by), and the human-acceptance guard on `→ Done`.

  Idempotent: if a system Task type already exists in the workspace, it is a
  no-op. Runs with a system actor (bypasses member policies) so it can be
  invoked from the signup Reactor before the user has any other context.
  """
  require Ash.Query

  alias Concept.Objects.{ObjectType, Workflow, WorkflowState, Transition, FieldDef}

  @system %{system?: true}

  @states [
    {"Backlog", :backlog, true},
    {"Todo", :todo, false},
    {"Doing", :doing, false},
    {"Review", :review, false},
    {"Done", :done, false},
    {"Canceled", :canceled, false}
  ]

  @doc """
  Seed (or return the existing) Task type for `workspace_id`.
  Returns `{:ok, %ObjectType{}}`.
  """
  def seed_task_type(workspace_id) do
    case existing_task_type(workspace_id) do
      nil -> create_task_type(workspace_id)
      type -> {:ok, type}
    end
  end

  defp existing_task_type(workspace_id) do
    ObjectType
    |> Ash.Query.filter(key == "task" and is_system? == true)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
    |> List.first()
  end

  defp create_task_type(workspace_id) do
    {:ok, wf} =
      Workflow
      |> Ash.Changeset.for_create(:create, %{name: "Default"}, actor: @system, tenant: workspace_id)
      |> Ash.create()

    states = create_states(wf, workspace_id)
    create_done_guard_transition(wf, states, workspace_id)

    {:ok, type} =
      ObjectType
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Task", key: "task", icon: "✓", is_system?: true, workflow_id: wf.id},
        actor: @system,
        tenant: workspace_id
      )
      |> Ash.create()

    create_fields(type, workspace_id)
    {:ok, type}
  end

  defp create_states(wf, workspace_id) do
    Enum.reduce(@states, %{}, fn {name, cat, initial}, acc ->
      {:ok, state} =
        WorkflowState
        |> Ash.Changeset.for_create(
          :create,
          %{workflow_id: wf.id, name: name, category: cat, is_initial?: initial},
          actor: @system,
          tenant: workspace_id
        )
        |> Ash.create()

      Map.put(acc, cat, state)
    end)
  end

  # The default linear flow + the human-acceptance gate on → Done.
  defp create_done_guard_transition(wf, states, workspace_id) do
    edges = [
      {:backlog, :todo, []},
      {:todo, :doing, []},
      {:doing, :review, []},
      {:review, :done, [%{"kind" => "requires_approval", "config" => %{"by" => "creator"}}]},
      {:todo, :canceled, []},
      {:doing, :canceled, []}
    ]

    for {from, to, guards} <- edges do
      {:ok, _} =
        Transition
        |> Ash.Changeset.for_create(
          :create,
          %{
            workflow_id: wf.id,
            from_state_id: states[from].id,
            to_state_id: states[to].id,
            guards: guards
          },
          actor: @system,
          tenant: workspace_id
        )
        |> Ash.create()
    end
  end

  defp create_fields(type, workspace_id) do
    fields = [
      %{name: "Title", field_type: :text, is_title?: true, required?: true},
      %{
        name: "Priority",
        field_type: :select,
        config: %{"options" => ["low", "normal", "high"], "default" => "normal"}
      },
      %{name: "Blocked by", key: "blocked_by", field_type: :relation, config: %{"many" => true}}
    ]

    for attrs <- fields do
      {:ok, _} =
        FieldDef
        |> Ash.Changeset.for_create(
          :create,
          Map.put(attrs, :object_type_id, type.id),
          actor: @system,
          tenant: workspace_id
        )
        |> Ash.create()
    end
  end
end
