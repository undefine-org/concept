defmodule ConceptWeb.PageTreeTest do
  @moduledoc """
  Sidebar page tree affordances. BUG-064: the archive control used an ellipsis
  glyph (reads as "more options") and fired immediately with no confirmation —
  a destructive action one stray hover-click away from the add-subpage button.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tree#{System.unique_integer([:positive])}@example.com",
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
    {:ok, page} = Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  describe "archive affordance (BUG-064)" do
    test "archive button is confirmed and reads as archive, not 'more options'",
         %{conn: conn, ws: ws, page: page} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      archive_btn = "button[phx-click='archive_page'][phx-value-id='#{page.id}']"

      # Destructive action must be confirmed before dispatching.
      assert has_element?(view, "#{archive_btn}[data-confirm]"),
             "archive must prompt confirmation (data-confirm)"

      # Affordance must read as archive — an archive-box glyph, not an ellipsis
      # ("more options") which mis-signals a menu.
      assert has_element?(view, "#{archive_btn} .hero-archive-box-micro"),
             "archive button should use an archive-semantic icon"

      refute has_element?(view, "#{archive_btn} .hero-ellipsis-horizontal-micro"),
             "ellipsis glyph mis-signals 'more options' for a destructive action"
    end

    test "archive_page still routes through to the domain (page archived)",
         %{conn: conn, user: user, ws: ws, page: page} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

      assert has_element?(view, "a[href$='/p/#{page.id}']", "Roadmap")

      view
      |> element("button[phx-click='archive_page'][phx-value-id='#{page.id}']")
      |> render_click()

      # PageTree forwards archive to WorkspaceLive via send(self(), …); flush the
      # mailbox so the archive handler runs before we assert.
      _ = :sys.get_state(view.pid)

      # Archived pages drop out of default reads (AshArchival FilterArchived).
      assert {:error, _} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    end
  end
end
