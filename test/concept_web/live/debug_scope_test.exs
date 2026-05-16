defmodule ConceptWeb.DebugScopeTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "debug#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Debug", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "page route assigns", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    state = :sys.get_state(view.pid)
    IO.inspect(state.socket.assigns, label: "ALL ASSIGNS", limit: :infinity)
    assert state.socket.assigns[:current_scope] != nil, "current_scope is nil!"
  end

  test "page route current_user", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    state = :sys.get_state(view.pid)
    IO.inspect(state.socket.assigns[:current_user], label: "CURRENT USER")
    assert state.socket.assigns[:current_user] != nil, "current_user is nil!"
  end
end
