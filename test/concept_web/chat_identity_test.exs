defmodule ConceptWeb.ChatIdentityTest do
  @moduledoc """
  R1 — message sender identity in the stream. My own messages render right
  (mine, no avatar); other members render left with a colored avatar + name.
  A channel reads as multi-party, not a monologue.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Repo
  import Ecto.Query

  defp make_user(prefix) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{prefix}#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    user
  end

  setup %{conn: conn} do
    user = make_user("me")

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    peer = make_user("peer")
    {:ok, _} = Accounts.add_member(ws.id, to_string(peer.email), actor: user)
    {:ok, conn: conn, user: user, ws: ws, peer: peer}
  end

  test "my message renders mine (right), the peer's renders other (left) with a name", ctx do
    {:ok, m1} =
      Chat.create_message(%{text: "mine text", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, _m2} =
      Chat.create_message(%{text: "peer text", addresses_host: false},
        actor: ctx.peer,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: m1.conversation_id}
      )

    {:ok, view, _html} =
      live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels/#{m1.conversation_id}")

    html = render(view)

    # Both alignment classes are present (a two-party conversation).
    assert html =~ "ora-chat-message--mine"
    assert html =~ "ora-chat-message--other"
    # The peer is named by their email-derived label.
    assert html =~ to_string(ctx.peer.email)
  end

  test "consecutive same-sender messages group into one run (R1b)", ctx do
    {:ok, m1} =
      Chat.create_message(%{text: "first of run", addresses_host: false},
        actor: ctx.peer,
        tenant: ctx.ws.id
      )

    {:ok, _m2} =
      Chat.create_message(%{text: "second of run", addresses_host: false},
        actor: ctx.peer,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: m1.conversation_id}
      )

    {:ok, view, _html} =
      live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels/#{m1.conversation_id}")

    # The first message of the run starts it; the second is a continuation.
    assert has_element?(view, "[data-starts-run='true']")
    assert has_element?(view, "[data-starts-run='false'].ora-chat-row--cont")
    # The run head shows the sender name; the continuation row does not (the
    # name lives only on the run-start row, not per message).
    cont_row =
      view
      |> element("[data-starts-run='false'].ora-chat-row--cont")
      |> render()

    refute cont_row =~ to_string(ctx.peer.email)
  end
end
