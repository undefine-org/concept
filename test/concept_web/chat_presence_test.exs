defmodule ConceptWeb.ChatPresenceTest do
  @moduledoc """
  T3 — human presence + typing in chat. Reuses Phoenix.Presence (the editor's
  mechanism) on a per-conversation topic: online avatar dots in the header, and
  a "X is typing" cue for humans beside the host's "is thinking".
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
        email: "presence#{System.unique_integer([:positive])}@example.com",
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
      Chat.create_message(%{text: "presence probe", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, conn: conn, user: user, ws: ws, conversation_id: msg.conversation_id}
  end

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)

    view
    |> element("[data-testid=\"rail-conversation\"][phx-value-id='#{conversation_id}']")
    |> render_click()

    :timer.sleep(120)
  end

  test "opening a conversation tracks presence on its topic", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    presences =
      ConceptWeb.Presence.list("chat:conversation:#{ctx.conversation_id}:presence")

    assert Map.has_key?(presences, ctx.user.id)
  end

  test "a second member shows as an online presence dot", ctx do
    # A teammate present on the same conversation topic.
    teammate_id = Ash.UUID.generate()

    ConceptWeb.Presence.track(
      self(),
      "chat:conversation:#{ctx.conversation_id}:presence",
      teammate_id,
      %{display_name: "Teammate", color: "#2383E2", online_at: System.system_time(:second)}
    )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)
    # Nudge a presence recompute.
    send(view.pid, %Phoenix.Socket.Broadcast{
      topic: "chat:conversation:#{ctx.conversation_id}:presence",
      event: "presence_diff",
      payload: %{}
    })

    :timer.sleep(80)
    assert has_element?(view, "[id$='-chat-presence']")
  end

  test "switching conversations untracks presence on the previous one", ctx do
    # A second, DISTINCT conversation to switch to (explicit create so it is not
    # the workspace find-or-create target of ctx.conversation_id).
    {:ok, conv2} =
      Chat.create_conversation(%{host_type: :workspace, host_id: nil, workspace_id: ctx.ws.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, _m2} =
      Chat.create_message(%{text: "second conversation", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: conv2.id}
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert ConceptWeb.Presence.list("chat:conversation:#{ctx.conversation_id}:presence")
           |> Map.has_key?(ctx.user.id)

    # Switch directly to the second conversation (no close in between).
    view
    |> element("[data-testid=\"rail-conversation\"][phx-value-id='#{conv2.id}']")
    |> render_click()

    :timer.sleep(120)

    # No longer tracked on the first conversation; tracked on the second.
    refute ConceptWeb.Presence.list("chat:conversation:#{ctx.conversation_id}:presence")
           |> Map.has_key?(ctx.user.id)

    assert ConceptWeb.Presence.list("chat:conversation:#{conv2.id}:presence")
           |> Map.has_key?(ctx.user.id)
  end

  test "a peer's typing renders a typing cue in my view (two sessions)", ctx do
    # Peer A (me) opens the conversation.
    {:ok, view_a, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view_a, ctx.conversation_id)

    # Peer B: a second member, present + typing on the same conversation topic.
    {:ok, peer} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "peer#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    ConceptWeb.Presence.track(
      self(),
      "chat:conversation:#{ctx.conversation_id}:presence",
      peer.id,
      %{
        display_name: "Devin",
        color: "#2383E2",
        online_at: System.system_time(:second),
        typing: true
      }
    )

    # Nudge peer A to recompute presence.
    send(view_a.pid, %Phoenix.Socket.Broadcast{
      topic: "chat:conversation:#{ctx.conversation_id}:presence",
      event: "presence_diff",
      payload: %{}
    })

    :timer.sleep(80)
    html = render(view_a)
    assert html =~ "is typing"
    assert html =~ "Devin"
  end

  test "typing in the composer broadcasts a typing cue to others", ctx do
    # Observer session: a second connection tracking the same conversation that
    # should receive the typing presence update.
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    # Fire the composer change with a non-empty draft → typing on.
    view
    |> element("[id$='-composer'] form")
    |> render_change(%{"form" => %{"text" => "typing now"}})

    :timer.sleep(80)

    metas =
      ConceptWeb.Presence.get_by_key(
        "chat:conversation:#{ctx.conversation_id}:presence",
        ctx.user.id
      )

    typing? =
      case metas do
        %{metas: ms} -> Enum.any?(ms, &Map.get(&1, :typing, false))
        _ -> false
      end

    assert typing?
  end
end
