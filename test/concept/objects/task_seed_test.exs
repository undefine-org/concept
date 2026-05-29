defmodule Concept.Objects.TaskSeedTest do
  @moduledoc """
  Wave 3: the Task type is seeded per workspace on onboarding, and readiness
  (`ready_records`) derives from category :todo + unblocked + unassigned.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "seed_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    %{user: user, ws: ws.id}
  end

  describe "seeding" do
    test "onboarding seeds exactly one Task type with default workflow + fields", ctx do
      {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
      task_types = Enum.filter(types, &(&1.key == "task"))
      assert length(task_types) == 1
      task = hd(task_types)
      assert task.is_system?
      assert is_binary(task.workflow_id)

      {:ok, states} = Objects.list_workflow_states(task.workflow_id, actor: ctx.user, tenant: ctx.ws)
      cats = states |> Enum.map(& &1.category) |> Enum.sort()
      assert cats == Enum.sort([:backlog, :todo, :doing, :review, :done, :canceled])
      assert Enum.find(states, & &1.is_initial?).category == :backlog

      {:ok, fields} = Objects.list_field_defs(task.id, actor: ctx.user, tenant: ctx.ws)
      keys = Enum.map(fields, & &1.key)
      assert "title" in keys
      assert "priority" in keys
      assert "blocked_by" in keys
    end

    test "seeding is idempotent", ctx do
      {:ok, t1} = Objects.Seeder.seed_task_type(ctx.ws)
      {:ok, t2} = Objects.Seeder.seed_task_type(ctx.ws)
      assert t1.id == t2.id

      {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
      assert Enum.count(types, &(&1.key == "task")) == 1
    end
  end

  describe "readiness" do
    setup ctx do
      {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
      task = Enum.find(types, &(&1.key == "task"))
      {:ok, states} = Objects.list_workflow_states(task.workflow_id, actor: ctx.user, tenant: ctx.ws)
      by_cat = Map.new(states, &{&1.category, &1})
      {:ok, fields} = Objects.list_field_defs(task.id, actor: ctx.user, tenant: ctx.ws)
      blocked_by = Enum.find(fields, &(&1.key == "blocked_by"))
      %{task: task, states: by_cat, blocked_by: blocked_by}
    end

    defp mk(ctx, title) do
      {:ok, r} =
        Objects.create_record(ctx.task.id, %{fields: %{"title" => title}},
          actor: ctx.user,
          tenant: ctx.ws
        )

      r
    end

    # Walk the seeded workflow graph to reach `cat`.
    # Edges: nil->backlog (initial), backlog->todo->doing->review->done.
    @path %{
      backlog: [:backlog],
      todo: [:backlog, :todo],
      doing: [:backlog, :todo, :doing],
      review: [:backlog, :todo, :doing, :review],
      done: [:backlog, :todo, :doing, :review, :done]
    }

    @linear [:backlog, :todo, :doing, :review, :done]

    defp put_state(ctx, rec, cat) do
      target_idx = Enum.find_index(@linear, &(&1 == cat))
      current_idx = current_index(ctx, rec)
      steps = Enum.slice(@linear, (current_idx + 1)..target_idx)

      Enum.reduce(steps, rec, fn step_cat, acc ->
        {:ok, r} =
          Concept.Objects.transition_record(acc, ctx.states[step_cat].id,
            actor: ctx.user,
            tenant: ctx.ws
          )

        r
      end)
    end

    defp current_index(ctx, rec) do
      cat = Enum.find_value(ctx.states, fn {c, s} -> if s.id == rec.state_id, do: c end)
      Enum.find_index(@linear, &(&1 == cat)) || -1
    end

    test "a todo, unassigned, unblocked record is ready", ctx do
      r = mk(ctx, "A") |> then(&put_state(ctx, &1, :todo))

      {:ok, ready} = Objects.ready_records(ctx.task.id, actor: ctx.user, tenant: ctx.ws)
      assert Enum.any?(ready, &(&1.id == r.id))
    end

    test "a doing record is not ready (wrong category)", ctx do
      r = mk(ctx, "B") |> then(&put_state(ctx, &1, :doing))
      {:ok, ready} = Objects.ready_records(ctx.task.id, actor: ctx.user, tenant: ctx.ws)
      refute Enum.any?(ready, &(&1.id == r.id))
    end

    test "an assigned todo record is not ready", ctx do
      r = mk(ctx, "C") |> then(&put_state(ctx, &1, :todo))
      {:ok, _} = Objects.assign_record(r, ctx.user.id, actor: ctx.user, tenant: ctx.ws)
      {:ok, ready} = Objects.ready_records(ctx.task.id, actor: ctx.user, tenant: ctx.ws)
      refute Enum.any?(ready, &(&1.id == r.id))
    end

    test "a todo record blocked by an unfinished task is not ready; becomes ready when blocker done", ctx do
      blocker = mk(ctx, "blocker") |> then(&put_state(ctx, &1, :todo))
      blocked = mk(ctx, "blocked") |> then(&put_state(ctx, &1, :todo))

      {:ok, _} =
        Objects.link_records(blocked.id, blocker.id, ctx.blocked_by.id,
          actor: ctx.user,
          tenant: ctx.ws
        )

      {:ok, ready} = Objects.ready_records(ctx.task.id, actor: ctx.user, tenant: ctx.ws)
      refute Enum.any?(ready, &(&1.id == blocked.id)), "blocked task must not be ready"
      assert Enum.any?(ready, &(&1.id == blocker.id)), "blocker itself is ready"

      # finish the blocker
      _ = put_state(ctx, blocker, :done)

      {:ok, ready2} = Objects.ready_records(ctx.task.id, actor: ctx.user, tenant: ctx.ws)
      assert Enum.any?(ready2, &(&1.id == blocked.id)), "unblocked task becomes ready"
    end
  end
end
