defmodule ConceptWeb.ChatThreadsTest do
  @moduledoc """
  T2 — threads made visible. A thread is a child conversation seeded from a
  message (seed_message_id). The stream shows a "N replies" chip under a seeded
  message; Reply-in-thread spawns/continues the child conversation; a docked
  thread panel shows the seed + the child conversation.
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
        email: "thread#{System.unique_integer([:positive])}@example.com",
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

    # A conversation with a parent message and a thread seeded from it.
    {:ok, seed} =
      Chat.create_message(%{text: "parent message", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, _reply} =
      Chat.create_message(
        %{text: "first thread reply", addresses_host: false, reply_to_message_id: seed.id},
        actor: user,
        tenant: ws.id
      )

    {:ok, conn: conn, user: user, ws: ws, seed: seed, conversation_id: seed.conversation_id}
  end

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
    view |> element("button[phx-value-id='#{conversation_id}']") |> render_click()
    :timer.sleep(100)
  end

  test "a seeded message shows a thread chip with the reply count", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # The seed message renders a thread chip (it has one reply).
    assert has_element?(view, "[id$='-thread-chip-#{ctx.seed.id}']")
    assert render(view) =~ "1 reply"
  end

  test "opening a thread shows the docked thread panel with the seed pinned", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    view |> element("[id$='-thread-chip-#{ctx.seed.id}']") |> render_click()
    :timer.sleep(80)

    panel = view |> element("[id$='-thread-panel']") |> render()
    assert panel =~ "Thread"
    assert panel =~ "parent message"
    assert panel =~ "first thread reply"
  end

  test "replying in the thread adds a message to the child conversation", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)
    view |> element("[id$='-thread-chip-#{ctx.seed.id}']") |> render_click()
    :timer.sleep(80)

    [thread] = Chat.thread_for_seed!(ctx.seed.id, actor: ctx.user, tenant: ctx.ws.id)
    before = Chat.message_history!(thread.id, tenant: ctx.ws.id) |> length()

    view
    |> element("[id$='-thread-reply-form']")
    |> render_submit(%{"form" => %{"text" => "another thread reply"}})

    :timer.sleep(150)
    after_ = Chat.message_history!(thread.id, tenant: ctx.ws.id) |> length()
    assert after_ == before + 1
  end

  test "a message with no thread shows no chip", ctx do
    # A fresh standalone message with no replies.
    {:ok, lone} =
      Chat.create_message(%{text: "lonely", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, lone.conversation_id)

    refute has_element?(view, "[id$='-thread-chip-#{lone.id}']")
  end
end
