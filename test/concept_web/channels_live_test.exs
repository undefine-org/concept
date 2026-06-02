defmodule ConceptWeb.ChannelsLiveTest do
  @moduledoc """
  Channels — the full-screen projection of the conversation substrate. The
  sidebar "Channels" link navigates to /w/:slug/channels (a real route, not the
  overlay panel); a conversation id in the path deep-links into a thread.
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
        email: "channels#{System.unique_integer([:positive])}@example.com",
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

    {:ok, [_ | _] = wss} = Accounts.Workspace.for_user(user.id, actor: user)
    ws = hd(wss)
    {:ok, page} = Pages.create_page("Launch Plan", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "sidebar shows a Channels link to the full-screen route", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    assert has_element?(view, "a[href='/w/#{ctx.ws.slug}/channels']", "Channels")
  end

  test "the channels route renders the full-screen chat (rail visible)", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")
    assert has_element?(view, "#channels-shell")
    # The rail (host > conversation nav) renders, not hidden behind a panel.
    assert has_element?(view, "nav[aria-label='Conversations']")
    assert has_element?(view, "#channels-chat-#{ctx.ws.id}-new-conversation")
  end

  test "a conversation id in the path deep-links into that thread", ctx do
    {:ok, msg} =
      Chat.create_message(
        %{text: "deep link target", addresses_host: true, host_type: :page, host_id: ctx.page.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} =
      live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels/#{msg.conversation_id}")

    assert has_element?(view, "#channels-shell")
    assert render(view) =~ "deep link target"
  end

  test "the channels home shows stat cards when nothing is selected", ctx do
    # A conversation exists, but the full-screen view lands on the home (it does
    # not auto-resume), so the stat overview renders.
    {:ok, _msg} =
      Chat.create_message(%{text: "seed", addresses_host: true},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")

    assert has_element?(view, "[id$='-home']")
    assert has_element?(view, ".ora-stat-card")
    assert render(view) =~ "Jump back in"
  end

  test "the sidebar Channels link shows an unread badge", ctx do
    # A fresh conversation the actor authored: cursor nil → unread → badge shows.
    {:ok, _msg} =
      Chat.create_message(%{text: "unread one", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")
    assert has_element?(view, "#sidebar-unread-badge")
  end
end
