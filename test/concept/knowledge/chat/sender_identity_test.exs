defmodule Concept.Knowledge.Chat.SenderIdentityTest do
  @moduledoc """
  Every human-sent message is attributed to its author's participant
  (`sender_participant_id`). This is the identity that lets a projection
  distinguish "me" from another member — the foundation of the left/right
  message split. Host turns (the grounded voice) remain unattributed (NULL).
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

  setup do
    user = make_user("sender")
    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, user: user, ws: ws}
  end

  test "a human message is stamped with the sender's participant id", ctx do
    {:ok, msg} =
      Chat.create_message(%{text: "hello team", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    refute is_nil(msg.sender_participant_id)

    # The stamped participant resolves to this user's membership.
    parts =
      Chat.participants_for_conversation!(msg.conversation_id,
        actor: ctx.user,
        tenant: ctx.ws.id,
        load: [:membership]
      )

    mine = Enum.find(parts, &(&1.id == msg.sender_participant_id))
    assert mine
    assert mine.membership.user_id == ctx.user.id
  end

  test "two members' messages carry distinct sender ids", ctx do
    peer = make_user("peer")
    {:ok, _} = Accounts.add_member(ctx.ws.id, to_string(peer.email), actor: ctx.user)

    {:ok, m1} =
      Chat.create_message(%{text: "from me", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, m2} =
      Chat.create_message(%{text: "from peer", addresses_host: false},
        actor: peer,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: m1.conversation_id}
      )

    refute is_nil(m1.sender_participant_id)
    refute is_nil(m2.sender_participant_id)
    refute m1.sender_participant_id == m2.sender_participant_id
  end
end
