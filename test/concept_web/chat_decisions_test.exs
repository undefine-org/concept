defmodule ConceptWeb.ChatDecisionsTest do
  @moduledoc """
  T5 — decisions. A conversation has a lifecycle (:open → :decided). The header
  Decide button transitions it; a decided conversation shows a badge and can
  reopen. The task engine and the conversation engine are the same engine.
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
        email: "decide#{System.unique_integer([:positive])}@example.com",
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
      Chat.create_message(%{text: "should we decide?", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, conn: conn, user: user, ws: ws, conversation_id: msg.conversation_id}
  end

  test "a conversation starts open", ctx do
    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.state == :open
  end

  test "decide transitions the conversation to decided", ctx do
    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    {:ok, decided} = Chat.decide_conversation(conv, %{}, actor: ctx.user, tenant: ctx.ws.id)
    assert decided.state == :decided

    {:ok, reopened} = Chat.reopen_conversation(decided, %{}, actor: ctx.user, tenant: ctx.ws.id)
    assert reopened.state == :open
  end

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    view
    |> element("button[phx-click=\"select_conversation\"][phx-value-id='#{conversation_id}']")
    |> render_click()

    :timer.sleep(120)
  end

  test "the header Decide button marks the conversation decided", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert has_element?(view, "[id$='-decide-btn']")
    view |> element("[id$='-decide-btn']") |> render_click()
    :timer.sleep(80)

    # Badge appears; the conversation is decided.
    assert has_element?(view, "[id$='-decided-badge']")
    # R3: Reopen is a real pill button (padded, filled), not bare text.
    assert has_element?(view, "button[id$='-reopen-btn'].rounded-full.bg-notion-sidebar")

    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.state == :decided
  end

  test "a decided conversation can be reopened from the header", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)
    view |> element("[id$='-decide-btn']") |> render_click()
    :timer.sleep(60)

    view |> element("[id$='-reopen-btn']") |> render_click()
    :timer.sleep(80)

    assert has_element?(view, "[id$='-decide-btn']")
    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.state == :open
  end
end
