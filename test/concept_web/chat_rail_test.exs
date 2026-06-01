defmodule ConceptWeb.ChatRailTest do
  @moduledoc """
  T1 — the adaptive channel rail in the chat panel. A page host with several
  conversations renders as a collapsible category; a host with one renders
  inline. Glyphs are host-native (no Slack '#'). Driven through the real
  WorkspaceLive chat panel.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rail#{System.unique_integer([:positive])}@example.com",
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
    {:ok, conn: conn, user: user, ws: ws}
  end

  defp open_chat(view) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
  end

  # Force two distinct conversations on the same page host.
  defp seed_page_conversations(ctx, n) do
    {:ok, page} =
      Pages.create_page("Offline Sync", ctx.ws.id, nil, actor: ctx.user, tenant: ctx.ws.id)

    for i <- 1..n do
      {:ok, conv} =
        Chat.create_conversation(%{host_type: :page, host_id: page.id, workspace_id: ctx.ws.id},
          actor: ctx.user,
          tenant: ctx.ws.id
        )

      {:ok, _m} =
        Chat.create_message(
          %{text: "topic #{i}", host_type: :page, host_id: page.id, addresses_host: false},
          actor: ctx.user,
          tenant: ctx.ws.id,
          private_arguments: %{conversation_id: conv.id}
        )
    end

    page
  end

  test "a page host with >=2 conversations renders a collapsible category", ctx do
    page = seed_page_conversations(ctx, 2)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    html = render(view)

    # The page title is a category header (not a flat conversation row).
    assert html =~ "Offline Sync"
    # The category toggle button is present and host-keyed.
    assert has_element?(view, "button[phx-value-key='page:#{page.id}']")
  end

  test "collapsing a category hides its conversations", ctx do
    page = seed_page_conversations(ctx, 2)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)

    # Expanded by default → the host's conversation rows are present. Titles are
    # async (generate_name Oban), so assert on the rendered row count, not text.
    expanded = render(view)
    rows_expanded = expanded |> String.split("phx-value-id") |> length()

    view
    |> element("button[phx-value-key='page:#{page.id}']")
    |> render_click()

    # Collapsed → fewer select_conversation rows than when expanded.
    collapsed = render(view)
    rows_collapsed = collapsed |> String.split("phx-value-id") |> length()
    assert rows_collapsed < rows_expanded
  end

  test "a host with exactly one conversation renders inline (no category toggle)", ctx do
    page = seed_page_conversations(ctx, 1)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)

    # Inline mode → no collapsible category button for this host…
    refute has_element?(view, "button[phx-value-key='page:#{page.id}']")
    # …but the single conversation is still selectable inline, and its page
    # label (the inline host ref) is present.
    assert has_element?(view, "button[phx-value-id]")
    assert render(view) =~ "Offline Sync"
  end

  test "the New conversation (host-picker) entry is present", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    assert render(view) =~ "New conversation"
  end

  test "rail uses host-native glyphs, never a Slack hashtag channel", ctx do
    seed_page_conversations(ctx, 2)
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    html = render(view)
    # Host-native document glyph for a page host; no "# channelname" pattern.
    assert html =~ "hero-document-text"
    refute html =~ "># Offline Sync"
  end
end
