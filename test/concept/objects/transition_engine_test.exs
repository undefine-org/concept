defmodule Concept.Objects.TransitionEngineTest do
  @moduledoc """
  Wave 2 integration: build a workflow (states + guarded transitions), attach
  it to an object type, and drive a record through transitions — asserting the
  graph is enforced and guards block/allow correctly.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wf_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # Workflow: Backlog(initial) -> Todo -> Doing -> Review -> Done
    {:ok, wf} = Objects.create_workflow("Default", actor: user, tenant: ws.id)

    states =
      for {name, cat, init} <- [
            {"Backlog", :backlog, true},
            {"Todo", :todo, false},
            {"Doing", :doing, false},
            {"Review", :review, false},
            {"Done", :done, false}
          ] do
        attrs = %{workflow_id: wf.id, name: name, category: cat, is_initial?: init}

        {:ok, s} =
          Concept.Objects.WorkflowState
          |> Ash.Changeset.for_create(:create, attrs, actor: user, tenant: ws.id)
          |> Ash.create()

        {cat, s}
      end
      |> Map.new()

    # object type using this workflow
    {:ok, type} = Objects.create_object_type("Task", actor: user, tenant: ws.id)
    {:ok, type} = Ash.update(type, %{workflow_id: wf.id}, action: :set_workflow, actor: user, tenant: ws.id)

    {:ok, _} =
      Concept.Objects.FieldDef
      |> Ash.Changeset.for_create(
        :create,
        %{object_type_id: type.id, name: "Title", field_type: :text, is_title?: true},
        actor: user,
        tenant: ws.id
      )
      |> Ash.create()

    {:ok, _} =
      Concept.Objects.FieldDef
      |> Ash.Changeset.for_create(
        :create,
        %{object_type_id: type.id, name: "PR", field_type: :url},
        actor: user,
        tenant: ws.id
      )
      |> Ash.create()

    %{user: user, ws: ws.id, wf: wf, states: states, type: type}
  end

  defp transition(ctx, from, to, guards \\ []) do
    {:ok, t} =
      Concept.Objects.Transition
      |> Ash.Changeset.for_create(
        :create,
        %{
          workflow_id: ctx.wf.id,
          from_state_id: ctx.states[from].id,
          to_state_id: ctx.states[to].id,
          guards: guards
        },
        actor: ctx.user,
        tenant: ctx.ws
      )
      |> Ash.create()

    t
  end

  defp new_record(ctx, fields \\ %{}) do
    {:ok, rec} =
      Objects.create_record(ctx.type.id, %{fields: Map.merge(%{"title" => "T"}, fields)},
        actor: ctx.user,
        tenant: ctx.ws
      )

    rec
  end

  test "can enter the initial state from nil", ctx do
    rec = new_record(ctx)
    assert rec.state_id == nil

    {:ok, rec} =
      Objects.transition_record(rec, ctx.states[:backlog].id, actor: ctx.user, tenant: ctx.ws)

    assert rec.state_id == ctx.states[:backlog].id
  end

  test "cannot enter a non-initial state from nil", ctx do
    rec = new_record(ctx)
    assert {:error, _} =
             Objects.transition_record(rec, ctx.states[:doing].id, actor: ctx.user, tenant: ctx.ws)
  end

  test "follows defined transitions and rejects undefined ones", ctx do
    transition(ctx, :backlog, :todo)

    rec = new_record(ctx)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:backlog].id, actor: ctx.user, tenant: ctx.ws)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:todo].id, actor: ctx.user, tenant: ctx.ws)
    assert rec.state_id == ctx.states[:todo].id

    # No transition Todo -> Done defined
    assert {:error, _} =
             Objects.transition_record(rec, ctx.states[:done].id, actor: ctx.user, tenant: ctx.ws)
  end

  test "requires_proof guard blocks until field present", ctx do
    transition(ctx, :backlog, :doing)
    transition(ctx, :doing, :review, [%{"kind" => "requires_proof", "config" => %{"field" => "pr"}}])

    rec = new_record(ctx)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:backlog].id, actor: ctx.user, tenant: ctx.ws)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:doing].id, actor: ctx.user, tenant: ctx.ws)

    # No PR yet -> blocked
    assert {:error, _} =
             Objects.transition_record(rec, ctx.states[:review].id, actor: ctx.user, tenant: ctx.ws)

    {:ok, rec} =
      Objects.update_record_fields(rec, %{"title" => "T", "pr" => "https://github.com/x/y/pull/1"},
        actor: ctx.user,
        tenant: ctx.ws
      )

    {:ok, rec} =
      Objects.transition_record(rec, ctx.states[:review].id, actor: ctx.user, tenant: ctx.ws)

    assert rec.state_id == ctx.states[:review].id
  end

  test "requires_approval by creator gates the done transition", ctx do
    transition(ctx, :backlog, :review)

    transition(ctx, :review, :done, [
      %{"kind" => "requires_approval", "config" => %{"by" => "creator"}}
    ])

    # A second user (member) who is NOT the creator
    {:ok, other} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "other_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, _} =
      Concept.Accounts.Membership.create(ctx.ws, other.id, :member, actor: %{system?: true})

    rec = new_record(ctx)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:backlog].id, actor: ctx.user, tenant: ctx.ws)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:review].id, actor: ctx.user, tenant: ctx.ws)

    # Non-creator blocked
    assert {:error, _} =
             Objects.transition_record(rec, ctx.states[:done].id, actor: other, tenant: ctx.ws)

    # Creator allowed
    {:ok, rec} =
      Objects.transition_record(rec, ctx.states[:done].id, actor: ctx.user, tenant: ctx.ws)

    assert rec.state_id == ctx.states[:done].id
  end

  test "multiple guard failures are aggregated", ctx do
    transition(ctx, :backlog, :done, [
      %{"kind" => "requires_proof", "config" => %{"field" => "pr"}},
      %{"kind" => "requires_fields", "config" => %{"fields" => ["missing_field"]}}
    ])

    rec = new_record(ctx)
    {:ok, rec} = Objects.transition_record(rec, ctx.states[:backlog].id, actor: ctx.user, tenant: ctx.ws)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Objects.transition_record(rec, ctx.states[:done].id, actor: ctx.user, tenant: ctx.ws)

    msg = Enum.map_join(errors, " ", fn e -> Map.get(e, :message, "") end)
    assert msg =~ "pr"
    assert msg =~ "missing_field"
  end
end
