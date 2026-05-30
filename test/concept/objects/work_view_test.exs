defmodule Concept.Objects.WorkViewTest do
  @moduledoc """
  Pull-model `Objects.work_view/1`: cross-type aggregation of "what's assigned
  to me" + "what's ready to pick up" + blocked-id badging. Mirrors the
  readiness fixtures in `engine_test.exs` but spans two object types to prove
  the view is type-agnostic.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "work_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    ws = workspace.id

    # Two object types sharing one workflow with a :todo and :done state.
    {:ok, type_a} = Objects.create_object_type("Alpha", actor: user, tenant: ws)
    {:ok, type_b} = Objects.create_object_type("Beta", actor: user, tenant: ws)

    {:ok, wf} = Objects.create_workflow("Default", actor: user, tenant: ws)
    {:ok, todo} = Objects.create_workflow_state(wf.id, "Todo", :todo, actor: user, tenant: ws)
    {:ok, done} = Objects.create_workflow_state(wf.id, "Done", :done, actor: user, tenant: ws)

    # Records land in :todo on create (initial), and may move :todo -> :done.
    {:ok, _} = Objects.mark_workflow_state_initial(todo, actor: user, tenant: ws)
    {:ok, _} = Objects.create_transition(wf.id, todo.id, done.id, actor: user, tenant: ws)

    {:ok, _} = Objects.set_object_type_workflow(type_a.id, wf.id, actor: user, tenant: ws)
    {:ok, _} = Objects.set_object_type_workflow(type_b.id, wf.id, actor: user, tenant: ws)

    %{user: user, ws: ws, type_a: type_a, type_b: type_b, todo: todo, done: done}
  end

  # Records start in the initial (:todo) state on create.
  defp todo_record(ctx, type, title) do
    {:ok, rec} =
      Objects.create_record(type.id, %{fields: %{"title" => title}}, actor: ctx.user, tenant: ctx.ws)

    rec
  end

  test "ready spans every object type", ctx do
    a = todo_record(ctx, ctx.type_a, "alpha task")
    b = todo_record(ctx, ctx.type_b, "beta task")

    {:ok, view} = Objects.work_view(actor: ctx.user, tenant: ctx.ws)
    ready_ids = MapSet.new(view.ready, & &1.id)

    assert MapSet.member?(ready_ids, a.id)
    assert MapSet.member?(ready_ids, b.id)
  end

  test "ready excludes assigned and non-todo records", ctx do
    assigned = todo_record(ctx, ctx.type_a, "claimed")
    {:ok, _} = Objects.assign_record(assigned, ctx.user.id, actor: ctx.user, tenant: ctx.ws)

    finished = todo_record(ctx, ctx.type_a, "finished")
    {:ok, _} = Objects.transition_record(finished, ctx.done.id, actor: ctx.user, tenant: ctx.ws)

    {:ok, view} = Objects.work_view(actor: ctx.user, tenant: ctx.ws)
    ready_ids = MapSet.new(view.ready, & &1.id)

    refute MapSet.member?(ready_ids, assigned.id)
    refute MapSet.member?(ready_ids, finished.id)
  end

  test "mine returns records assigned to the actor with state + type loaded", ctx do
    rec = todo_record(ctx, ctx.type_a, "mine")
    {:ok, _} = Objects.assign_record(rec, ctx.user.id, actor: ctx.user, tenant: ctx.ws)

    {:ok, view} = Objects.work_view(actor: ctx.user, tenant: ctx.ws)
    mine = Enum.find(view.mine, &(&1.id == rec.id))

    assert mine
    assert %Concept.Objects.WorkflowState{} = mine.state
    assert %Concept.Objects.ObjectType{} = mine.object_type
  end

  test "blocked_ids flags assigned records with an incomplete blocker", ctx do
    blocker = todo_record(ctx, ctx.type_a, "blocker")
    blocked = todo_record(ctx, ctx.type_a, "blocked")
    {:ok, _} = Objects.assign_record(blocked, ctx.user.id, actor: ctx.user, tenant: ctx.ws)

    {:ok, rel} =
      Objects.create_field_def(
        %{
          object_type_id: ctx.type_a.id,
          name: "Blocked by",
          key: "blocked_by",
          field_type: :relation
        },
        actor: ctx.user,
        tenant: ctx.ws
      )

    {:ok, _} = Objects.link_records(blocked.id, blocker.id, rel.id, actor: ctx.user, tenant: ctx.ws)

    {:ok, view} = Objects.work_view(actor: ctx.user, tenant: ctx.ws)
    assert MapSet.member?(view.blocked_ids, blocked.id)

    # finishing the blocker clears the flag
    {:ok, _} = Objects.transition_record(blocker, ctx.done.id, actor: ctx.user, tenant: ctx.ws)
    {:ok, view2} = Objects.work_view(actor: ctx.user, tenant: ctx.ws)
    refute MapSet.member?(view2.blocked_ids, blocked.id)
  end
end
