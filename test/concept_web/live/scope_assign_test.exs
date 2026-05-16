defmodule ConceptWeb.ScopeAssignTest do
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
        email: "scopeassign#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Confirm user directly
    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    # Sign in to get token
    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Test Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "current_scope has user, workspace, and role on :page route", %{
    conn: conn,
    user: user,
    ws: ws,
    page: page
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    state = :sys.get_state(view.pid)
    scope = state.socket.assigns.current_scope

    assert scope.user.id == user.id
    assert scope.workspace.id == ws.id
    assert scope.role == :owner
  end

  test "compute_scope produces nil-workspace scope when no workspace_slug in params", %{
    user: user
  } do
    # on_mount for the :index route has no workspace_slug in params
    scope = ConceptWeb.LiveUserAuth.compute_scope(user, %{}, nil)

    assert scope.user.id == user.id
    assert scope.workspace == nil
    assert scope.role == nil
  end
end
