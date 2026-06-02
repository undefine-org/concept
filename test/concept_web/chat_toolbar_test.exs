defmodule ConceptWeb.ChatToolbarTest do
  @moduledoc """
  T2 — the per-message hover toolbar. Every message is a unit of work: reply in
  thread, copy a link. (React arrives in T4, Crystallize-this-message in T6 once
  message bodies are blocks.) The toolbar's actions are real now or absent — no
  dead buttons.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "toolbar#{System.unique_integer([:positive])}@example.com",
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

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, msg} =
      Chat.create_message(%{text: "a message to act on", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, conn: conn, user: user, ws: ws, msg: msg, conversation_id: msg.conversation_id}
  end

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    view
    |> element("[data-testid=\"rail-conversation\"][phx-value-id='#{conversation_id}']")
    |> render_click()

    :timer.sleep(100)
  end

  test "each message renders a hover toolbar with reply + copy-link", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert has_element?(view, "[id$='-msg-toolbar-#{ctx.msg.id}']")
    # Reply-in-thread action present, targeting this message as the seed.
    assert has_element?(
             view,
             "[phx-click='open_thread'][phx-value-seed='#{ctx.msg.id}']"
           )

    # Copy-link action present (client-side clipboard).
    assert has_element?(view, "[id$='-msg-copylink-#{ctx.msg.id}']")
  end

  test "the toolbar reply opens the thread panel for that message", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # Use the toolbar's reply (open_thread) on a message with no thread yet.
    view
    |> element("[id$='-msg-toolbar-#{ctx.msg.id}'] [phx-click='open_thread']")
    |> render_click()

    :timer.sleep(80)
    panel = view |> element("[id$='-thread-panel']") |> render()
    assert panel =~ "Thread"
    assert panel =~ "a message to act on"
  end

  test "closing a toolbar-opened (threadless) panel does not crash", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # Open a thread on a message with NO replies (thread: nil in open_thread).
    view
    |> element("[id$='-msg-toolbar-#{ctx.msg.id}'] [phx-click='open_thread']")
    |> render_click()

    :timer.sleep(60)
    # Closing must not raise on the nil thread (regression: ot.thread.id).
    view |> element("[id$='-thread-panel'] [phx-click='close_thread']") |> render_click()
    :timer.sleep(60)

    refute has_element?(view, "[id$='-thread-panel']")
  end

  test "replying via the toolbar-opened panel spawns the thread", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    view
    |> element("[id$='-msg-toolbar-#{ctx.msg.id}'] [phx-click='open_thread']")
    |> render_click()

    :timer.sleep(80)

    # No thread existed; this first reply must spawn the child conversation.
    view
    |> element("[id$='-thread-reply-form']")
    |> render_submit(%{"form" => %{"text" => "spawned via toolbar"}})

    :timer.sleep(150)
    threads = Chat.thread_for_seed!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)
    assert length(threads) == 1
  end
end
