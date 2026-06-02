defmodule ConceptWeb.ChatSeenByTest do
  @moduledoc """
  T3 — seen-by read receipts. Participants whose read cursor has reached the
  latest message render as small stacked avatars beneath it (the trust signal
  teams expect), derived from last_read_message_id.
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
        email: "seen#{System.unique_integer([:positive])}@example.com",
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

    teammate = make_user("seenmate")
    {:ok, _m} = Accounts.add_member(ws.id, to_string(teammate.email), actor: user)

    {:ok, msg} =
      Chat.create_message(%{text: "seen probe", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    # Join the teammate to the conversation so they can have a read cursor.
    {:ok, mate_membership} = Accounts.get_membership(teammate.id, ws.id, actor: user)

    {:ok, _p} =
      Chat.join_conversation(
        %{
          workspace_id: ws.id,
          conversation_id: msg.conversation_id,
          membership_id: mate_membership.id
        },
        actor: user,
        tenant: ws.id
      )

    {:ok,
     conn: conn,
     user: user,
     ws: ws,
     teammate: teammate,
     mate_membership: mate_membership,
     conversation_id: msg.conversation_id,
     msg: msg}
  end

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

  defp open_conversation(view, conversation_id) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
    view |> element("button[phx-value-id='#{conversation_id}']") |> render_click()
    :timer.sleep(120)
  end

  test "a teammate who has read the latest message appears in seen-by", ctx do
    # Advance the teammate's cursor to the latest message.
    [mate_participant] =
      Chat.participants_for_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
      |> Enum.filter(&(&1.membership_id == ctx.mate_membership.id))

    {:ok, _} =
      Chat.mark_participant_read(mate_participant, %{last_read_message_id: ctx.msg.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    assert has_element?(view, "[id$='-seen-by']")
  end

  test "no seen-by when no other participant has caught up", ctx do
    # Teammate's cursor stays nil (default) → nobody else has read the latest.
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_conversation(view, ctx.conversation_id)

    refute has_element?(view, "[id$='-seen-by']")
  end
end
