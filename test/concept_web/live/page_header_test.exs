defmodule ConceptWeb.PageHeaderTest do
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

  test "page header live_component is present", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "#page-header-#{page.id}")
  end

  test "title element is contenteditable", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "h1#page-title-#{page.id}[contenteditable=\"true\"]")
  end

  test "title h1 sets phx-update=ignore so the caret survives re-renders (BUG-062)",
       %{conn: conn, ws: ws, page: page} do
    # The ContentEditable hook owns the h1's DOM (user types directly into it).
    # Per the LiveView guideline, a hook managing its own DOM MUST set
    # phx-update=ignore; otherwise a parent re-render (emoji toggle, presence,
    # remote edit) patches innerText back to @page.title and resets the caret
    # to position 0 mid-edit.
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "h1#page-title-#{page.id}[phx-update=\"ignore\"]"),
           "editable title must carry phx-update=ignore (hook owns its DOM)"
  end

  describe "popover click-away (BUG-063)" do
    test "emoji popover closes on outside click", %{conn: conn, ws: ws, page: page} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
      header = element(view, "#page-header-#{page.id}")

      render_hook(header, "toggle_emoji_picker", %{})
      assert has_element?(view, ".ora-emoji-picker-popover")
      # The open popover must carry a click-away binding (no inline JS).
      assert has_element?(view, ".ora-emoji-picker-popover[phx-click-away]")

      render_hook(header, "close_emoji_picker", %{})
      refute has_element?(view, ".ora-emoji-picker-popover")
    end

    test "cover popover closes on outside click", %{conn: conn, ws: ws, page: page} do
      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
      header = element(view, "#page-header-#{page.id}")

      render_hook(header, "toggle_cover_picker", %{})
      assert has_element?(view, ".ora-cover-picker-popover")
      assert has_element?(view, ".ora-cover-picker-popover[phx-click-away]")

      render_hook(header, "close_cover_picker", %{})
      refute has_element?(view, ".ora-cover-picker-popover")
    end
  end

  test "save_title updates the page", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    # Find the PageHeader live_component and trigger save_title
    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => "Renamed"})

    # Verify the page was renamed in DB
    {:ok, updated} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    assert updated.title == "Renamed"
  end

  test "renamed title appears in rendered output", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => "Renamed"})

    # Re-render and check title appears
    html = render(view)
    assert html =~ "Renamed"
  end

  test "empty title falls back to placeholder", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => ""})

    # Title element should be empty (placeholder handled by CSS ::before)
    assert has_element?(view, "h1#page-title-#{page.id}")

    # Check page is empty title in DB
    {:ok, updated} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    assert updated.title == ""
  end

  test "remote save_title updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "save_title", %{"value" => "Renamed"})

    # In test transactions Ash defers PubSub broadcasts, so we emit the broadcast
    # that production would send.
    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:pages",
      %Phoenix.Socket.Broadcast{
        event: "page_updated",
        payload: %{data: %{page | title: "Renamed"}}
      }
    )

    # The title h1 uses phx-update=ignore, so the server publishes the canonical
    # value via data-title (attributes ARE patched under ignore). The visible
    # text is applied by the ContentEditable hook when unfocused (JS, not run by
    # LiveViewTest), so we assert the server-observable contract: data-title.
    assert render(view2) =~ "Renamed"
    assert has_element?(view2, ~s(h1#page-title-#{page.id}[data-title="Renamed"]))
  end

  test "remote set_emoji updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "set_emoji", %{"emoji" => "🚀"})

    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:pages",
      %Phoenix.Socket.Broadcast{
        event: "page_updated",
        payload: %{data: %{page | icon_emoji: "🚀"}}
      }
    )

    assert render(view2) =~ "🚀"
  end

  test "remote set_cover_color updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "set_cover_color", %{"color" => "blue"})

    Phoenix.PubSub.broadcast!(
      Concept.PubSub,
      "workspace:#{ws.id}:pages",
      %Phoenix.Socket.Broadcast{
        event: "page_updated",
        payload: %{data: %{page | cover_color: :blue}}
      }
    )

    assert render(view2) =~ "ora-cover-blue"
  end

  test "real notifier broadcast updates LV2 cross-tab without manual broadcast", %{
    conn: conn,
    ws: ws,
    page: page
  } do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    # Sanity: both views start with the original title in the page header and sidebar.
    assert has_element?(view2, "h1#page-title-#{page.id}", "Roadmap")
    assert render(view2) =~ "Roadmap"

    # LV1 dispatches the real production save_title path. NO manual broadcast.
    view1
    |> element("#page-header-#{page.id}")
    |> render_hook("save_title", %{"value" => "Cross-Tab Renamed"})

    # LV2 must receive the page_updated event via Ash.Notifier.PubSub → Phoenix.PubSub
    # and update both the page header live_component and the sidebar PageTree.
    html2 = render(view2)

    # Server-observable contract under phx-update=ignore: data-title carries the
    # canonical value; the hook applies the visible text when unfocused.
    assert has_element?(view2, ~s(h1#page-title-#{page.id}[data-title="Cross-Tab Renamed"]))
    assert html2 =~ "Cross-Tab Renamed"
    # Original title in the sidebar tree is replaced.
    refute has_element?(view2, "aside.ora-sidebar a[href$=\"/p/#{page.id}\"]", "Roadmap")
  end

  test "page_updated broadcasts exactly once per rename", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> element("#page-header-#{page.id}")
    |> render_hook("save_title", %{"value" => "Once Only"})

    assert_receive %Phoenix.Socket.Broadcast{event: "page_updated"}, 500
    refute_receive %Phoenix.Socket.Broadcast{event: "page_updated"}, 200
  end
end
