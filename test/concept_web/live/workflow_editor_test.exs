defmodule ConceptWeb.WorkflowEditorTest do
  @moduledoc "E2: workflow editor — states, initial, transitions, guards (list-first)."
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wfe_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # A fresh custom type starts with NO workflow.
    {:ok, type} = Objects.create_object_type("Customer", actor: user, tenant: ws.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user, ws: ws, type: type}
  end

  defp reload_type(type, user, ws) do
    {:ok, t} = Objects.get_object_type(type.id, actor: user, tenant: ws.id)
    t
  end

  test "creates a workflow for a type that has none", ctx do
    refute ctx.type.workflow_id

    {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")
    assert render(view) =~ "no workflow yet"

    view |> element("#workflow-editor button", "Add a workflow") |> render_click()

    t = reload_type(ctx.type, ctx.user, ctx.ws)
    assert t.workflow_id
  end

  describe "with a workflow" do
    setup ctx do
      {:ok, wf} = Objects.create_workflow("WF", actor: ctx.user, tenant: ctx.ws.id)
      {:ok, type} = Objects.set_object_type_workflow(ctx.type, wf.id, actor: ctx.user, tenant: ctx.ws.id)
      %{type: type, workflow_id: wf.id}
    end

    test "adds states; the first is initial", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      view
      |> form("#add-state-form", %{"name" => "Lead", "category" => "backlog"})
      |> render_submit()

      view
      |> form("#add-state-form", %{"name" => "Active", "category" => "doing"})
      |> render_submit()

      {:ok, states} =
        Objects.list_workflow_states(ctx.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

      names = Enum.map(states, & &1.name)
      assert "Lead" in names
      assert "Active" in names

      lead = Enum.find(states, &(&1.name == "Lead"))
      active = Enum.find(states, &(&1.name == "Active"))
      assert lead.is_initial?
      refute active.is_initial?
      assert active.category == :doing
    end

    test "recategorizes a state via the inline form", ctx do
      {:ok, st} =
        Objects.create_workflow_state(ctx.workflow_id, "Lead", :backlog,
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      view
      |> element("#state-#{st.id} form")
      |> render_change(%{"state_id" => st.id, "name" => "Lead", "category" => "todo"})

      {:ok, [reloaded]} = filter_states(ctx, "Lead")
      assert reloaded.category == :todo
    end

    test "adds a transition between two states", ctx do
      {:ok, a} =
        Objects.create_workflow_state(ctx.workflow_id, "Lead", :backlog, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, b} =
        Objects.create_workflow_state(ctx.workflow_id, "Active", :doing, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      view
      |> form("#add-transition-form", %{"from" => a.id, "to" => b.id})
      |> render_submit()

      {:ok, transitions} =
        Objects.list_transitions(ctx.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

      assert Enum.any?(transitions, &(&1.from_state_id == a.id and &1.to_state_id == b.id))
    end

    test "adds, configures, and removes a guard on a transition", ctx do
      {:ok, a} =
        Objects.create_workflow_state(ctx.workflow_id, "Doing", :doing, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, b} =
        Objects.create_workflow_state(ctx.workflow_id, "Review", :review, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, t} =
        Objects.create_transition(ctx.workflow_id, a.id, b.id, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      # add a requires_proof guard
      view
      |> element("#transition-#{t.id} form[phx-submit=add_guard]")
      |> render_submit(%{"transition_id" => t.id, "kind" => "requires_proof"})

      {:ok, [t1]} = filter_transitions(ctx, a.id, b.id)
      assert [%{"kind" => "requires_proof"}] = t1.guards

      # configure its field key
      view
      |> element("#transition-#{t.id} form[phx-change=update_guard]")
      |> render_change(%{"transition_id" => t.id, "index" => "0", "field" => "pr_url"})

      {:ok, [t2]} = filter_transitions(ctx, a.id, b.id)
      assert [%{"kind" => "requires_proof", "config" => %{"field" => "pr_url"}}] = t2.guards

      # remove it
      view
      |> element("#transition-#{t.id} button[phx-click=remove_guard]")
      |> render_click()

      {:ok, [t3]} = filter_transitions(ctx, a.id, b.id)
      assert t3.guards == []
    end

    test "setting a new initial state clears the previous one", ctx do
      {:ok, a} =
        Objects.create_workflow_state(ctx.workflow_id, "Lead", :backlog, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, _} = Objects.mark_workflow_state_initial(a, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, b} =
        Objects.create_workflow_state(ctx.workflow_id, "Active", :doing, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      view
      |> element("#state-#{b.id} button[phx-click=make_initial]")
      |> render_click()

      {:ok, states} =
        Objects.list_workflow_states(ctx.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

      initials = Enum.filter(states, & &1.is_initial?)
      assert length(initials) == 1
      assert hd(initials).id == b.id
    end

    test "a requires_fields guard stores a list and renders without crashing", ctx do
      {:ok, a} =
        Objects.create_workflow_state(ctx.workflow_id, "Doing", :doing, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, b} =
        Objects.create_workflow_state(ctx.workflow_id, "Done", :done, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, t} =
        Objects.create_transition(ctx.workflow_id, a.id, b.id, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      view
      |> element("#transition-#{t.id} form[phx-submit=add_guard]")
      |> render_submit(%{"transition_id" => t.id, "kind" => "requires_fields"})

      # submit a comma-string; it must be normalized to a list and not crash
      view
      |> element("#transition-#{t.id} form[phx-change=update_guard]")
      |> render_change(%{"transition_id" => t.id, "index" => "0", "fields" => "owner, due_date"})

      {:ok, [t1]} = filter_transitions(ctx, a.id, b.id)
      assert [%{"kind" => "requires_fields", "config" => %{"fields" => ["owner", "due_date"]}}] = t1.guards

      # re-render must succeed (describe over a list, not a string)
      assert render(view) =~ "requires fields: owner, due_date"
    end

    test "a crafted guard event with a non-integer index does not crash", ctx do
      {:ok, a} =
        Objects.create_workflow_state(ctx.workflow_id, "S1", :todo, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, b} =
        Objects.create_workflow_state(ctx.workflow_id, "S2", :doing, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, t} =
        Objects.create_transition(ctx.workflow_id, a.id, b.id, actor: ctx.user, tenant: ctx.ws.id)

      {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/types/#{ctx.type.id}")

      # a crafted event with a non-integer index must not crash the LiveView
      # (parent ignores unknown events; component guards with Integer.parse)
      render_hook(view, "remove_guard", %{"transition_id" => t.id, "index" => "not_an_int"})
      assert Process.alive?(view.pid)
    end
  end

  defp filter_states(ctx, name) do
    {:ok, states} =
      Objects.list_workflow_states(ctx.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, Enum.filter(states, &(&1.name == name))}
  end

  defp filter_transitions(ctx, from_id, to_id) do
    {:ok, transitions} =
      Objects.list_transitions(ctx.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, Enum.filter(transitions, &(&1.from_state_id == from_id and &1.to_state_id == to_id))}
  end
end
