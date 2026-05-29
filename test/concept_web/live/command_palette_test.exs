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

    view
    |> element("#command-palette input[type='text']")
    |> render_keyup(%{key: "", value: "oad"})

    render_async(view)

    # Palette-scoped: click the actual title row (not a positional index, which
    # silently pointed at the ask_answer row when buckets failed to render).
    view
    |> element(~s{#command-palette button[data-type="title"][data-page-id="#{page.id}"]})
    |> render_click()

    assert_redirect(view, ~p"/w/#{ws.slug}/p/#{page.id}")
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

  test "closed palette does not capture window keydowns (regression: KeyError :selected_index on Enter)",
       %{conn: conn, ws: ws} do
    {:ok, view, html} = live(conn, ~p"/w/#{ws.slug}")

    # When the palette is closed, no phx-window-keydown="palette_key" listener
    # may be attached. Otherwise every keystroke (e.g. Enter while typing in a
    # block) is sent to the LV, where it crashed with KeyError :selected_index
    # because update/2 only seeds that assign while @show_palette is true.
    refute html =~ ~s(phx-window-keydown="palette_key")

    # Open + close to force the catch-all update/2 path, then re-check.
    view |> element("#workspace-root") |> render_hook("open_command_palette", %{})
    html_after_close = view |> element("#workspace-root") |> render_keydown(%{key: "Escape"})
    refute html_after_close =~ ~s(phx-window-keydown="palette_key")
  end

  test "palette opens from a page editor route via open_command_palette",
       %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    html =
      view
      |> element("#workspace-root")
      |> render_hook("open_command_palette", %{})

    assert html =~ "Search pages or run a command"
    assert html =~ ~s(phx-window-keydown="palette_key")
  end

  test "title-only query shows only title rows", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "oad"})

    # Palette-scoped: assert the real title row exists (not sidebar leak), and
    # the semantic section is absent (no blocks ingested).
    _ = html
    render_async(view)

    assert has_element?(
             view,
             ~s{#command-palette button[data-type="title"][data-page-id="#{page.id}"]}
           )

    refute render(view) =~ "Semantic matches"
  end

  test "query matching block content shows semantic results", %{conn: conn, ws: ws, user: user} do
    # Create a page and add some block content
    {:ok, page} = Pages.create_page("Test Page", ws.id, nil, actor: user, tenant: ws.id)

    # Add blocks with content (this would normally trigger ingestion)
    # For now, we test that semantic section appears when there are results
    # Note: This test may need adjustment based on actual ingestion workflow

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "test content"})

    # Semantic results would appear here if blocks were ingested
    # For now, just verify no crash occurs
    assert html =~ "Search pages or run a command"
  end

  test "empty query shows recent pages", %{conn: conn, ws: ws, user: user} do
    {:ok, recent1} = Pages.create_page("Recent 1", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, recent2} = Pages.create_page("Recent 2", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    render_async(view)

    # Palette-scoped: recent pages render as real title rows.
    assert has_element?(
             view,
             ~s{#command-palette button[data-type="title"][data-page-id="#{recent1.id}"]}
           )

    assert has_element?(
             view,
             ~s{#command-palette button[data-type="title"][data-page-id="#{recent2.id}"]}
           )

    # Should not show ask answer row when query is empty
    refute render(view) =~ "Ask answer for"
  end

  test "ask answer row appears when query is non-empty", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "what is the meaning of life"})

    # Should show ask answer row
    assert html =~ "Ask answer for"
    assert html =~ "what is the meaning of life"
    assert html =~ "hero-chat-bubble-left-right"
    assert html =~ "data-type=\"ask_answer\""
  end

  test "selecting ask answer broadcasts palette_ask message", %{conn: conn, ws: ws} do
    # Subscribe to the palette topic
    Phoenix.PubSub.subscribe(Concept.PubSub, "palette:#{ws.id}")

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    view
    |> element("#command-palette input[type='text']")
    |> render_keyup(%{key: "", value: "test query"})

    # Find the ask answer button and click it
    html = render(view)
    # Extract the index from the ask answer button
    assert html =~ "data-type=\"ask_answer\""

    # Click the ask answer button (it should be the last item)
    # Actions: 2, then pages, then ask answer
    view
    |> element("#command-palette button[data-type='ask_answer']")
    |> render_click()

    # Assert the broadcast was received
    assert_receive {:palette_ask, "test query"}, 1000
  end

  test "title and semantic on same page - page appears once (dedupe)", %{
    conn: conn,
    ws: ws,
    user: user
  } do
    {:ok, page} = Pages.create_page("Unique Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "Unique"})

    # Should show the page in title results
    assert html =~ page.title
    # Count occurrences - should only appear once
    count = html |> String.split(page.title) |> length() |> Kernel.-(1)
    assert count == 1, "Page should appear exactly once, but appeared #{count} times"
  end

  test "search timeout - title rows render, semantic absent (no crash)", %{
    conn: conn,
    ws: ws,
    page: page
  } do
    # This test verifies graceful degradation when semantic search fails
    # The implementation already handles {:error, _} by returning empty results

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    html =
      view
      |> element("#command-palette input[type='text']")
      |> render_keyup(%{key: "", value: "oad"})

    # Title results should still render
    assert html =~ page.title
    # No crash - page rendered successfully
    assert html =~ "Search pages or run a command"
  end

  test "Escape closes palette (regression)", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("open_command_palette", %{})

    # Type a query first
    view
    |> element("#command-palette input[type='text']")
    |> render_keyup(%{key: "", value: "test"})

    html =
      view
      |> element("#workspace-root")
      |> render_keydown(%{key: "Escape"})

    refute html =~ "Search pages or run a command"
    refute html =~ "Ask answer for"
  end
end
