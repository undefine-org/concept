defmodule ConceptWeb.ChatAddPeopleTest do
  @moduledoc """
  T1 — the "Add people" modal: the UI for Participant.join. Adds a workspace
  member to a conversation as a participant. The host's grounded voice is a
  fixed, non-removable presence (a voice, not a member).
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
    user = make_user("owner")

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [_ | _] = wss} = Accounts.Workspace.for_user(user.id, actor: user)
    ws = hd(wss)

    # A second workspace member to add.
    teammate = make_user("mate")
    {:ok, _m} = Accounts.add_member(ws.id, teammate.email, actor: user)

    # A workspace conversation to add people to.
    {:ok, msg} =
      Chat.create_message(%{text: "kickoff", addresses_host: false}, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, teammate: teammate, conversation_id: msg.conversation_id}
  end

  defp open_chat(view) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
  end

  test "the participant rail exposes an Add people trigger", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    # Select the seeded conversation so the participant rail renders.
    view |> element("button[phx-value-id='#{ctx.conversation_id}']") |> render_click()
    :timer.sleep(80)
    assert has_element?(view, "[id$='-add-people-trigger']")
  end

  test "opening the modal lists workspace members and the fixed host voice", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    view |> element("button[phx-value-id='#{ctx.conversation_id}']") |> render_click()
    :timer.sleep(80)
    view |> element("[id$='-add-people-trigger']") |> render_click()

    dialog = view |> element("[id$='-add-people-dialog']") |> render()
    # Host voice present as a fixed chip; the teammate listed as addable.
    assert dialog =~ "AI voice" or dialog =~ "voice"
    assert dialog =~ to_string(ctx.teammate.email)
  end

  test "selecting a member and confirming joins them as a participant", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    view |> element("button[phx-value-id='#{ctx.conversation_id}']") |> render_click()
    :timer.sleep(80)
    view |> element("[id$='-add-people-trigger']") |> render_click()

    before =
      Chat.participants_for_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
      |> length()

    # Toggle the teammate's checkbox then confirm.
    {:ok, membership} =
      Accounts.get_membership(ctx.teammate.id, ctx.ws.id, actor: ctx.user)

    view
    |> element("[phx-click='toggle_member_pick'][phx-value-id='#{membership.id}']")
    |> render_click()

    view |> element("[id$='-add-people-confirm']") |> render_click()
    :timer.sleep(120)

    after_ =
      Chat.participants_for_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
      |> length()

    assert after_ == before + 1
  end
end
