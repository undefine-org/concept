defmodule ConceptWeb.ChatPeekTest do
  @moduledoc """
  Page peek — the bottom-right "Chat" button opens a page-scoped drawer (the
  ChatPanel) whose rail is narrowed to the current page's conversations, with an
  "Open in Channels" link that deep-links into the full-screen ChannelsLive.
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
        email: "peek#{System.unique_integer([:positive])}@example.com",
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
    {:ok, page} = Pages.create_page("Peek Page", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "a bottom-right Chat button is present on a page", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/p/#{ctx.page.id}")
    assert has_element?(view, "#open-chat-peek")
  end

  test "clicking the Chat button opens the page peek drawer with Open-in-Channels", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/p/#{ctx.page.id}")

    view |> element("#open-chat-peek") |> render_click()

    # The peek opens, titled by the page, with the deep-link to Channels.
    assert has_element?(view, ".ora-chat-panel")
    assert has_element?(view, "#peek-open-in-channels")
    assert has_element?(view, "a[href='/w/#{ctx.ws.slug}/channels']")
  end

  test "the peek rail is scoped to the current page's conversations", ctx do
    # A conversation on THIS page, and one on the workspace (different host).
    {:ok, _on_page} =
      Chat.create_message(
        %{text: "about this page", addresses_host: true, host_type: :page, host_id: ctx.page.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, _elsewhere} =
      Chat.create_message(
        %{text: "workspace topic", addresses_host: true, host_type: :workspace, host_id: nil},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/p/#{ctx.page.id}")
    view |> element("#open-chat-peek") |> render_click()

    html = render(view)
    # Page-scoped: the page's conversation shows, the workspace one does not.
    assert html =~ "about this page"
    refute html =~ "workspace topic"
  end
end
