defmodule Concept.Objects.Seeder do
  @moduledoc """
  Seeds the built-in **Task** object type into a workspace.

  Task is *not* special-cased machinery: it is a `Concept.Objects.Scaffold`
  type (default 6-category workflow + Title field) **plus** Task-specific
  extras — a `priority` select, a `blocked_by` relation, and the
  human-acceptance guard on the `Review → Done` transition. The scaffold is
  the single source of truth shared with the human "Create type" path
  (`Objects.scaffold_object_type/2`), so the built-in type and user types are
  built the same way.

  Idempotent: if a system Task type already exists in the workspace, it is a
  no-op. Runs with a system actor (bypasses member policies) so it can be
  invoked from the signup Reactor before the user has any other context.
  """
  require Ash.Query

  alias Concept.Objects.{FieldDef, ObjectType, Scaffold, Transition, WorkflowState}

  @system %{system?: true}
  @seed_opts [actor: @system, authorize?: false]

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
    opts = [tenant: workspace_id] ++ @seed_opts

    # Scaffold builds the usable base (default workflow + Title field); we then
    # pin the Task identity and layer on Task-specific fields + the acceptance
    # guard. Same path a human "Create type" takes, specialized for Task.
    {:ok, type} =
      Scaffold.object_type("Task", %{key: "task", icon: "✓", is_system?: true}, opts)

    add_task_fields(type, workspace_id)
    add_done_guard(type, workspace_id)
    {:ok, type}
  end

  defp add_task_fields(type, workspace_id) do
    fields = [
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

  # Task overrides the scaffold's guard-free `Review → Done` edge with the
  # human-acceptance gate (Symphony's accept step, expressed as data). The
  # scaffold already created the edge; we set its guards.
  defp add_done_guard(type, workspace_id) do
    states = states_by_category(type.workflow_id, workspace_id)
    review = states[:review]
    done = states[:done]

    transition =
      Transition
      |> Ash.Query.filter(
        workflow_id == ^type.workflow_id and from_state_id == ^review.id and
          to_state_id == ^done.id
      )
      |> Ash.Query.set_tenant(workspace_id)
      |> Ash.read!(actor: @system, authorize?: false)
      |> List.first()

    {:ok, _} =
      transition
      |> Ash.Changeset.for_update(
        :set_guards,
        %{guards: [%{"kind" => "requires_approval", "config" => %{"by" => "creator"}}]},
        actor: @system,
        tenant: workspace_id
      )
      |> Ash.update()
  end

  defp states_by_category(workflow_id, workspace_id) do
    WorkflowState
    |> Ash.Query.filter(workflow_id == ^workflow_id)
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read!(actor: @system, authorize?: false)
    |> Map.new(&{&1.category, &1})
  end
end
