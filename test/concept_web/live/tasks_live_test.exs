defmodule ConceptWeb.TasksLiveTest do
  @moduledoc "Wave 6: the Tasks board renders, creates, and moves tasks via the workflow graph."
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tlive_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # ConnCase doesn't auth by default; sign the user into the session.
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user, ws: ws}
  end

  test "renders the six workflow columns", %{conn: conn, ws: ws} do
    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/tasks")
    assert html =~ "Tasks"

    for cat <- ~w(backlog todo doing review done canceled) do
      assert html =~ ~s(id="col-#{cat}")
    end
  end

  test "creating a task adds it to the board", %{conn: conn, ws: ws, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/tasks")

    html =
      view
      |> form("#new-task-form", %{"title" => "Write the spec"})
      |> render_submit()

    assert html =~ "Write the spec"

    {:ok, types} = Objects.list_object_types(actor: user, tenant: ws.id)
    task = Enum.find(types, &(&1.key == "task"))
    {:ok, records} = Objects.list_records(task.id, actor: user, tenant: ws.id)
    assert Enum.any?(records, &(&1.title == "Write the spec"))
  end

  test "a new task can be moved Backlog → Todo via a move button", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    # New records auto-start in their workflow's initial state (Backlog), so a
    # freshly created task already shows the Backlog→Todo move button.
    {:ok, types} = Objects.list_object_types(actor: user, tenant: ws.id)
    task = Enum.find(types, &(&1.key == "task"))
    {:ok, states} = Objects.list_workflow_states(task.workflow_id, actor: user, tenant: ws.id)
    todo = Enum.find(states, &(&1.category == :todo))

    {:ok, rec} =
      Objects.create_record(task.id, %{fields: %{"title" => "Movable"}},
        actor: user,
        tenant: ws.id
      )

    assert rec.state_id != nil

    {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/tasks")

    view
    |> element(~s(#task-#{rec.id} button[phx-value-to="#{todo.id}"]))
    |> render_click()

    {:ok, reloaded} = Objects.get_record(rec.id, actor: user, tenant: ws.id)
    assert reloaded.state_id == todo.id
  end
end
