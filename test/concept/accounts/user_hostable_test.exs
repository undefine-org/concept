defmodule Concept.Accounts.UserHostableTest do
  @moduledoc """
  T5 — Accounts.User is Hostable (one stanza): a DM is a conversation hosted by
  a user. Verifies :user is a registered host type and a user-hosted message
  routes + resolves via for_host(:user), placing it in the rail's DM section.
  """
  use Concept.DataCase, async: false

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

  setup do
    user = make_user("hostowner")
    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    peer = make_user("hostpeer")
    {:ok, _} = Concept.Accounts.add_member(ws.id, to_string(peer.email), actor: user)
    {:ok, user: user, ws: ws, peer: peer}
  end

  test ":user is a registered Hostable type" do
    assert :user in Concept.Hostable.types()
  end

  test "a user-hosted message creates a DM conversation", ctx do
    {:ok, msg} =
      Chat.create_message(
        %{text: "dm hi", addresses_host: false, host_type: :user, host_id: ctx.peer.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    conv = Chat.get_conversation!(msg.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.host_type == :user
    assert conv.host_id == ctx.peer.id
  end

  test "for_host(:user) resolves the DM and the rail sections it under DMs", ctx do
    {:ok, _} =
      Chat.create_message(
        %{text: "dm hi", addresses_host: false, host_type: :user, host_id: ctx.peer.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    convs = Chat.conversations_for_host!(:user, ctx.peer.id, actor: ctx.user, tenant: ctx.ws.id)
    assert length(convs) >= 1

    [group | _] = Concept.Chat.RailModel.group_by_host(convs)
    assert group.host_type == :user
    assert Concept.Chat.RailModel.section_for(:user) == :direct_messages
  end
end
