defmodule ConceptWeb.ChatReactionsTest do
  @moduledoc """
  T4 — reaction chips + emoji picker in the chat UI. The toolbar react button
  opens a compact picker; choosing an emoji reacts; the chip shows a count and
  is outlined when the current user reacted; clicking own chip toggles it off.
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
        email: "rx#{System.unique_integer([:positive])}@example.com",
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
      Chat.create_message(%{text: "react in ui", addresses_host: false},
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

    :timer.sleep(120)
  end

  test "the toolbar exposes a react button that opens the emoji picker", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert has_element?(view, "[id$='-react-#{ctx.msg.id}']")

    view |> element("[id$='-react-#{ctx.msg.id}']") |> render_click()
    assert has_element?(view, "[id$='-emoji-pop-#{ctx.msg.id}']")
  end

  test "choosing an emoji reacts and renders a chip", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    view |> element("[id$='-react-#{ctx.msg.id}']") |> render_click()

    view
    |> element("[phx-click='react'][phx-value-message='#{ctx.msg.id}'][phx-value-emoji='👍']")
    |> render_click()

    :timer.sleep(80)

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert length(reactions) == 1
    assert has_element?(view, "[id$='-reactions-#{ctx.msg.id}']")
  end

  test "clicking an own reaction chip toggles it off", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # React first.
    view |> element("[id$='-react-#{ctx.msg.id}']") |> render_click()

    view
    |> element("[phx-click='react'][phx-value-message='#{ctx.msg.id}'][phx-value-emoji='👍']")
    |> render_click()

    :timer.sleep(60)

    # Click the chip (own reaction) to toggle off.
    view
    |> element(
      "[phx-click='toggle_reaction'][phx-value-message='#{ctx.msg.id}'][phx-value-emoji='👍']"
    )
    |> render_click()

    :timer.sleep(80)

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert reactions == []
  end
end
