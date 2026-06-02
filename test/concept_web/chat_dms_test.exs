defmodule ConceptWeb.ChatDmsTest do
  @moduledoc """
  T5 — DMs. A User is Hostable (one stanza), so a DM is a conversation hosted
  by a person. The host-picker offers people; conversations route to :user
  hosts; the rail places them in the Direct messages section.
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
    user = make_user("dmowner")

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    peer = make_user("dmpeer")
    {:ok, _} = Accounts.add_member(ws.id, to_string(peer.email), actor: user)

    {:ok, conn: conn, user: user, ws: ws, peer: peer}
  end

  test ":user is a registered host type", _ctx do
    assert :user in Concept.Hostable.types()
  end

  test "a message hosted by a user creates a DM conversation", ctx do
    {:ok, msg} =
      Chat.create_message(
        %{text: "hey there", addresses_host: false, host_type: :user, host_id: ctx.peer.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    conv = Chat.get_conversation!(msg.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.host_type == :user
    assert conv.host_id == ctx.peer.id
  end

  test "the host-picker offers people as DM hosts", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
    view |> element("[id$='-new-conversation']") |> render_click()

    picker = view |> element("[id$='-host-picker-dialog']") |> render()
    assert picker =~ "Direct messages"
    assert picker =~ to_string(ctx.peer.email)
  end

  test "starting a DM from the picker creates a user-hosted conversation", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
    view |> element("[id$='-new-conversation']") |> render_click()

    view
    |> element(
      "[phx-click='start_conversation'][phx-value-host-type='user'][phx-value-host-id='#{ctx.peer.id}']"
    )
    |> render_click()

    :timer.sleep(120)

    convs = Chat.conversations_for_host!(:user, ctx.peer.id, actor: ctx.user, tenant: ctx.ws.id)
    assert length(convs) >= 1
  end

  test "the rail places a user-hosted conversation in Direct messages", ctx do
    {:ok, _m} =
      Chat.create_message(
        %{text: "dm", addresses_host: false, host_type: :user, host_id: ctx.peer.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(120)
    assert render(view) =~ "Direct messages"
  end
end
