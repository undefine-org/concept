defmodule ConceptWeb.CommandPaletteTest do
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
        email: "palette#{System.unique_integer([:positive])}@example.com",
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
    {:ok, page} = Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)
    _ = Pages.create_page("Meeting Notes", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "Cmd-K opens command palette overlay", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    assert view
           |> element("#workspace-root")
           |> render_hook("open_command_palette", %{}) =~ "Search pages or run a command"
  end

  test "typing search query shows matching page", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "oad"})

    assert html =~ page.title
  end

  test "selecting a page result navigates to page", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    # Type search query
    view
    |> element("#command-palette input[type='text']")
    |> render_keyup(%{key: "", value: "oad"})

    # Click the page result (first action = index 0, second = index 1, first page = index 2)
    html =
      view
      |> element("#command-palette button[phx-value-index='2']")
      |> render_click()

    assert html =~ page.title
  end

  test "Escape closes palette", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#workspace-root")
      |> render_keydown(%{key: "Escape"})

    refute html =~ "Search pages or run a command"
  end
end
