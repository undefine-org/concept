defmodule Concept.Knowledge.Chat.PinTest do
  @moduledoc """
  R6 — pinned conversations. Pinning is per-member state on the Participant
  (pinned_at), mirroring the read cursor's grain. pin/unpin toggle it;
  my_pinned lists the actor's pinned conversations for the rail's Pinned
  section. Pins are private (one member's pin is invisible to others).
  """
  use Concept.DataCase, async: false

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

  defp my_participant(user, conversation_id, ws) do
    Chat.participants_for_conversation!(conversation_id,
      actor: user,
      tenant: ws.id,
      load: [:membership]
    )
    |> Enum.find(fn p -> match?(%{membership: %{user_id: uid}} when uid == user.id, p) end)
  end

  setup do
    user = make_user("pin")
    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, msg} =
      Chat.create_message(%{text: "pin me", addresses_host: false}, actor: user, tenant: ws.id)

    {:ok, user: user, ws: ws, conversation_id: msg.conversation_id}
  end

  test "pin then unpin toggles my_pinned membership", ctx do
    assert {:ok, []} = Chat.my_pinned_participants(actor: ctx.user, tenant: ctx.ws.id)

    mine = my_participant(ctx.user, ctx.conversation_id, ctx.ws)
    {:ok, pinned} = Chat.pin_participant(mine, actor: ctx.user, tenant: ctx.ws.id)
    refute is_nil(pinned.pinned_at)

    {:ok, [one]} = Chat.my_pinned_participants(actor: ctx.user, tenant: ctx.ws.id)
    assert one.conversation_id == ctx.conversation_id

    {:ok, unpinned} = Chat.unpin_participant(pinned, actor: ctx.user, tenant: ctx.ws.id)
    assert is_nil(unpinned.pinned_at)
    assert {:ok, []} = Chat.my_pinned_participants(actor: ctx.user, tenant: ctx.ws.id)
  end

  test "pins are private to the member", ctx do
    peer = make_user("pinpeer")
    {:ok, _} = Accounts.add_member(ctx.ws.id, to_string(peer.email), actor: ctx.user)
    # Peer joins the conversation by sending a message.
    {:ok, _} =
      Chat.create_message(%{text: "peer here", addresses_host: false},
        actor: peer,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: ctx.conversation_id}
      )

    mine = my_participant(ctx.user, ctx.conversation_id, ctx.ws)
    {:ok, _} = Chat.pin_participant(mine, actor: ctx.user, tenant: ctx.ws.id)

    # I see my pin; the peer sees none.
    assert {:ok, [_]} = Chat.my_pinned_participants(actor: ctx.user, tenant: ctx.ws.id)
    assert {:ok, []} = Chat.my_pinned_participants(actor: peer, tenant: ctx.ws.id)
  end
end
