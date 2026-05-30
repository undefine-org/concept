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
    assert render(view) =~ "No conversations yet"
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
    refute render(view) =~ "No conversations yet"
    assert render(view) =~ "About this workspace"
  end

  test "inbox re-streams on inbox_activity broadcast", %{conn: conn, user: user, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/inbox")
    assert render(view) =~ "No conversations yet"

    {:ok, _message} =
      Chat.create_message(
        %{text: "Ping", host_type: :workspace, addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    # The BroadcastInbox change fans out {:inbox_activity, _} to inbox:<user_id>,
    # which the LiveView subscribes to. Give the async broadcast a moment.
    :timer.sleep(100)
    refute render(view) =~ "No conversations yet"
  end
end
