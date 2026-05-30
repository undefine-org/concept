defmodule ConceptWeb.WorkLiveTest do
  @moduledoc """
  The pull-model Work surface: "My work" (assigned to me) + "Ready to pick"
  (unassigned, unblocked, todo) across all object types, with a Claim action
  and a blocked badge.
  """
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    password = "passw0rd!"

    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "work_#{System.unique_integer([:positive])}@example.com",
        password: password,
        password_confirmation: password
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # A workflow with todo + done; records start in todo (initial).
    {:ok, type} = Objects.create_object_type("Ticket", actor: user, tenant: ws.id)
    {:ok, wf} = Objects.create_workflow("Flow", actor: user, tenant: ws.id)
    {:ok, todo} = Objects.create_workflow_state(wf.id, "Todo", :todo, actor: user, tenant: ws.id)
    {:ok, done} = Objects.create_workflow_state(wf.id, "Done", :done, actor: user, tenant: ws.id)
    {:ok, _} = Objects.mark_workflow_state_initial(todo, actor: user, tenant: ws.id)
    {:ok, _} = Objects.create_transition(wf.id, todo.id, done.id, actor: user, tenant: ws.id)
    {:ok, _} = Objects.set_object_type_workflow(type.id, wf.id, actor: user, tenant: ws.id)

    {:ok, _} =
      Objects.create_field_def(type.id, "Title", :text, %{is_title?: true},
        actor: user,
        tenant: ws.id
      )

    conn = log_in_user(conn, user)
    %{conn: conn, user: user, ws: ws, type: type, todo: todo, done: done}
  end

  defp new_record(ctx, title) do
    {:ok, rec} =
      Objects.create_record(ctx.type.id, %{fields: %{"title" => title}},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    rec
  end

  test "ready records render and assigned records appear under My work", ctx do
    ready = new_record(ctx, "ready one")
    mine = new_record(ctx, "mine one")
    {:ok, _} = Objects.assign_record(mine, ctx.user.id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/work")

    assert has_element?(view, "#ready-#{ready.id}")
    assert has_element?(view, "#mine-#{mine.id}")
    # the assigned record is not offered for claiming
    refute has_element?(view, "#ready-#{mine.id}")
  end

  test "Claim assigns a ready record to me and moves it into My work", ctx do
    rec = new_record(ctx, "claim me")

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/work")
    assert has_element?(view, "#ready-#{rec.id}")

    view
    |> element("#ready-#{rec.id} button[phx-click='claim']")
    |> render_click()

    refute has_element?(view, "#ready-#{rec.id}")
    assert has_element?(view, "#mine-#{rec.id}")

    {:ok, reloaded} = Objects.get_record(rec.id, actor: ctx.user, tenant: ctx.ws.id)
    assert reloaded.assignee_id == ctx.user.id
  end

  test "a blocked assigned record shows the blocked badge", ctx do
    blocker = new_record(ctx, "blocker")
    blocked = new_record(ctx, "blocked")
    {:ok, _} = Objects.assign_record(blocked, ctx.user.id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, rel} =
      Objects.create_field_def(ctx.type.id, "Blocked by", :relation, %{key: "blocked_by"},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, _} =
      Objects.link_records(blocked.id, blocker.id, rel.id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/work")

    assert view |> element("#mine-#{blocked.id}") |> render() =~ "Blocked"
  end

  test "ready excludes records blocked by an unfinished dependency", ctx do
    blocker = new_record(ctx, "blocker")
    blocked = new_record(ctx, "blocked-ready")

    {:ok, rel} =
      Objects.create_field_def(ctx.type.id, "Blocked by", :relation, %{key: "blocked_by"},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, _} =
      Objects.link_records(blocked.id, blocker.id, rel.id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/work")

    # blocker is ready; blocked-ready is not (its dependency is unfinished)
    assert has_element?(view, "#ready-#{blocker.id}")
    refute has_element?(view, "#ready-#{blocked.id}")
  end
end
