defmodule ConceptWeb.ChatThinkingTest do
  @moduledoc """
  R2 — the host "is thinking" cue (and human typing cue) render INSIDE the
  message scroll viewport, after the stream, so they read as the live tail of
  the feed and scroll with it — not pinned above the composer.
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
        email: "think#{System.unique_integer([:positive])}@example.com",
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
    {:ok, conn: conn, user: user, ws: ws}
  end

  test "the message stream sits inside a scroll viewport that also holds the cues", ctx do
    {:ok, m} =
      Chat.create_message(%{text: "hi", addresses_host: false}, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels/#{m.conversation_id}")

    # The scroll viewport carries the ScrollToBottom hook; the stream is nested
    # within it (phx-update=stream admits only stream children, so the cues
    # live in the viewport beside the stream — this is what fixes their place).
    assert has_element?(view, "[id$='-scroll'][phx-hook='ScrollToBottom']")
    assert has_element?(view, "[id$='-scroll'] [id$='-message-container'][phx-update='stream']")
  end
end
