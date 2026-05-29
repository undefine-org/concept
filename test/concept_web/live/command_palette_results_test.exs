defmodule ConceptWeb.CommandPaletteResultsTest do
  @moduledoc """
  BUG-058: the palette's title/semantic result buckets are gated on
  `match?(%{ok?: true, result: %{title_results: _}}, @title_results)`, but
  `assign_async(:title_results, fn -> {:ok, %{title_results: pages}} end)`
  unwraps the *value* of the `:title_results` key, so `.result` is the bare
  list — the map-shaped guard never matches and the bucket never renders.

  These tests assert on PALETTE-SCOPED DOM (data-type="title" buttons), not on
  the page title text (which leaks from the always-present sidebar and produced
  false-greens in the older suite).
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.{Accounts, Pages, Repo}
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "palres#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, si} =
      Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", si.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  defp open(view) do
    view |> element("#workspace-root") |> render_hook("open_command_palette", %{})
    render_async(view)
  end

  defp search(view, q) do
    view |> element(~s{#command-palette input[type="text"]}) |> render_keyup(%{key: "", value: q})
    render_async(view)
  end

  test "matching query renders a title-result button in the palette", %{
    conn: conn,
    ws: ws,
    page: page
  } do
    {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
    open(view)
    _ = search(view, "oad")

    # Palette-scoped assertion: an actual selectable title row must exist.
    assert has_element?(
             view,
             ~s{#command-palette button[data-type="title"][data-page-id="#{page.id}"]}
           ),
           "expected a title result button for the matching page in the palette"
  end

  test "empty query renders recent pages as title rows", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
    open(view)
    render(view)

    assert has_element?(
             view,
             ~s{#command-palette button[data-type="title"][data-page-id="#{page.id}"]}
           ),
           "expected recent pages to render as title rows on empty query"
  end

  test "clicking a title row navigates to that page", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}")
    open(view)
    _ = search(view, "oad")

    view
    |> element(~s{#command-palette button[data-page-id="#{page.id}"]})
    |> render_click()

    # Navigation is driven by the parent LV (send(self(), {:palette_navigate, id})
    # -> push_navigate). assert_redirect observes the parent-level redirect.
    assert_redirect(view, ~p"/w/#{ws.slug}/p/#{page.id}")
  end
end
