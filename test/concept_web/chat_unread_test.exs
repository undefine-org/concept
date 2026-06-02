defmodule ConceptWeb.ChatUnreadTest do
  @moduledoc """
  T2 — unread state from the participant cursor. The conversation shows a "New"
  divider at the first message past my last_read_message_id, and advances the
  cursor (mark_read) when I view the latest message.
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
        email: "unread#{System.unique_integer([:positive])}@example.com",
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

    # Three messages; the participant cursor starts at nil (all unread).
    {:ok, m1} =
      Chat.create_message(%{text: "first msg", addresses_host: false}, actor: user, tenant: ws.id)

    {:ok, _m2} =
      Chat.create_message(%{text: "second msg", addresses_host: false},
        actor: user,
        tenant: ws.id,
        private_arguments: %{conversation_id: m1.conversation_id}
      )

    {:ok, conn: conn, user: user, ws: ws, conversation_id: m1.conversation_id, first_id: m1.id}
  end

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    view
    |> element("button[phx-click=\"select_conversation\"][phx-value-id='#{conversation_id}']")
    |> render_click()

    :timer.sleep(120)
  end

  test "an all-unread conversation shows a New divider", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert has_element?(view, "[id$='-unread-divider']")
    assert render(view) =~ "New"
  end

  test "marking read advances the cursor and clears the divider", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # Simulate the view-mark hook firing for the latest message.
    latest =
      Chat.message_history!(ctx.conversation_id, tenant: ctx.ws.id)
      |> List.first()

    view
    |> element("[id$='-message-container']")
    |> render_hook("mark_read", %{"message_id" => latest.id})

    :timer.sleep(80)

    # Cursor advanced for my participant.
    [participant] =
      Chat.participants_for_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)

    assert participant.last_read_message_id == latest.id

    # Re-opening now shows no New divider (all read).
    view
    |> element("button[phx-click=\"select_conversation\"][phx-value-id='#{ctx.conversation_id}']")
    |> render_click()

    :timer.sleep(100)
    refute has_element?(view, "[id$='-unread-divider']")
  end
end
