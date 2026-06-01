defmodule ConceptWeb.Components.WorkspaceShellTest do
  @moduledoc """
  Contract for `Layouts.workspace/1` — the single authed shell every signed-in
  surface renders through (D-1). Guards that the shared chrome (desktop sidebar,
  mobile hamburger bar, slide-in drawer + scrim) projects onto a real authed
  route, so board/work/inbox/page can never silently diverge again.

  We assert through a live board route rather than `render_component/2` because
  the shell embeds the sidebar's PageTree live_component, which needs a live
  cycle.
  """
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "shell_#{System.unique_integer([:positive])}@example.com",
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

  test "board route renders the unified shell chrome", %{conn: conn, ws: ws, type: type} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")

    # Desktop sidebar present (the chrome that board previously lacked, G19).
    assert has_element?(view, "aside.ora-sidebar")
    # Mobile affordances exist in the DOM (CSS gates visibility by breakpoint).
    assert has_element?(view, ".ora-mobile-bar")
    assert has_element?(view, "#ws-drawer")
    assert has_element?(view, "#ws-drawer-scrim")
    # The drawer wraps the same sidebar (no duplicate nav).
    assert has_element?(view, "#ws-drawer aside.ora-sidebar")
    # Canvas lives in the shared main region.
    assert has_element?(view, "main.ora-workspace-main")
  end

  test "no Phoenix flame logo anywhere in product chrome (G20)", %{
    conn: conn,
    ws: ws,
    type: type
  } do
    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")
    refute html =~ "logo.svg"
  end

  test "drawer is closed by default (translated off-canvas)", %{
    conn: conn,
    ws: ws,
    type: type
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/o/#{type.id}")
    # Closed-state class present; opening is a pure client JS toggle (no event).
    assert has_element?(view, "#ws-drawer.-translate-x-full")
    assert has_element?(view, "#ws-drawer-scrim.hidden")
  end
end
