defmodule ConceptWeb.InboxLiveTest do
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
        email: "inbox#{System.unique_integer([:positive])}@example.com",
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

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "inbox renders an empty state with no conversations", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/inbox")

    assert has_element?(view, "#inbox-list")
    # Empty state uses CSS `hidden only:block`, so its text is always in the DOM;
    # the meaningful signal is the ABSENCE of conversation rows (the `<a>` items).
    refute has_element?(view, "#inbox-list > a")
    # E-4: the empty state is the design-system empty_state primitive, not a
    # bare paragraph.
    assert has_element?(view, "#inbox-empty.ora-empty")
    assert render(view) =~ "Your inbox is clear"
  end

  test "inbox lists a conversation the user participates in", %{conn: conn, user: user, ws: ws} do
    # A host-addressed message find-or-creates a conversation and auto-joins the
    # sender as a participant — which is what places it in their inbox.
    {:ok, _message} =
      Chat.create_message(
        %{text: "Hello inbox", host_type: :workspace, addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/inbox")

    assert has_element?(view, "#inbox-list")
    # A real conversation row is present (an `<a>` stream item), and it carries
    # its host context.
    assert has_element?(view, "#inbox-list > a")
    assert render(view) =~ "About this workspace"
  end

  test "inbox re-streams on inbox_activity broadcast", %{conn: conn, user: user, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/inbox")
    refute has_element?(view, "#inbox-list > a")

    {:ok, message} =
      Chat.create_message(
        %{text: "Ping", host_type: :workspace, addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    # Drive the handler deterministically: broadcast the same payload the domain
    # fans out via BroadcastInbox. This exercises the LiveView's re-stream path
    # (the cross-process after_action broadcast is covered end-to-end in browser).
    Phoenix.PubSub.broadcast(
      Concept.PubSub,
      "inbox:#{user.id}",
      {:inbox_activity, %{conversation_id: message.conversation_id, message_id: message.id}}
    )

    assert render(view) =~ "About this workspace"
    assert has_element?(view, "#inbox-list > a")
  end
end
