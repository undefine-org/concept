defmodule ConceptWeb.ObjectBoardLiveTest do
  @moduledoc """
  Thread ① UI: the generic record board renders **any** object type at
  `/w/:slug/o/:type_id`, not just the built-in Task type. A user-created type
  (scaffolded with a default workflow + title field) must be immediately
  usable: see its columns, create a record into the initial state, and move it
  along the workflow — the database-builder thesis, reachable by a human.
  """
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ob_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    {:ok, type} = Objects.scaffold_object_type("Customer", actor: user, tenant: ws.id)

    %{conn: conn, user: user, ws: ws, type: type}
  end

  test "renders a custom type's board with its name and workflow columns", %{
    conn: conn,
    ws: ws,
    type: type
  } do
    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")
    assert html =~ "Customer"

    for cat <- ~w(backlog todo doing review done canceled) do
      assert html =~ ~s(id="col-#{cat}")
    end
  end

  test "creating a record on a custom board adds it to the initial column", %{
    conn: conn,
    ws: ws,
    user: user,
    type: type
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")

    html =
      view
      |> form("#new-task-form", %{"title" => "Acme Inc"})
      |> render_submit()

    assert html =~ "Acme Inc"

    {:ok, records} = Objects.list_records(type.id, actor: user, tenant: ws.id)
    assert Enum.any?(records, &(&1.title == "Acme Inc"))
  end

  test "a record on a custom board moves Backlog → Todo via a move button", %{
    conn: conn,
    ws: ws,
    user: user,
    type: type
  } do
    {:ok, states} = Objects.list_workflow_states(type.workflow_id, actor: user, tenant: ws.id)
    todo = Enum.find(states, &(&1.category == :todo))

    {:ok, rec} =
      Objects.create_record(type.id, %{fields: %{"title" => "Movable"}},
        actor: user,
        tenant: ws.id
      )

    {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")

    view
    |> element(~s(#task-#{rec.id} button[phx-value-to="#{todo.id}"]))
    |> render_click()

    {:ok, reloaded} = Objects.get_record(rec.id, actor: user, tenant: ws.id)
    assert reloaded.state_id == todo.id
  end

  test "the built-in Tasks route still resolves the seeded Task type", %{conn: conn, ws: ws} do
    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/tasks")
    assert html =~ "Tasks"
    assert html =~ ~s(id="col-todo")
  end

  test "the types index links to each type's board", %{conn: conn, ws: ws, type: type} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/types")
    assert has_element?(view, ~s(a[href="/w/#{ws.slug}/o/#{type.id}"]))
  end
end
