defmodule Concept.Knowledge.Chat.UnreadCountTest do
  @moduledoc """
  The cross-conversation unread signal that powers the sidebar "Channels" badge.
  `:my_unread` lists the actor's participant rows whose cursor is behind the
  conversation's latest message; `unread_count/1` is its COUNT. Reading a
  conversation (advancing the cursor to the latest) removes it from the set.
  """
  use Concept.DataCase, async: false

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Repo
  import Ecto.Query

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ucount#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, user: user, ws: ws}
  end

  test "a fresh conversation with messages is unread (cursor nil)", ctx do
    {:ok, _m} =
      Chat.create_message(%{text: "hello", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    assert Chat.unread_count(actor: ctx.user, tenant: ctx.ws.id) == 1
  end

  test "reading the latest message clears it from the unread set", ctx do
    {:ok, m1} =
      Chat.create_message(%{text: "one", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, m2} =
      Chat.create_message(%{text: "two", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id,
        private_arguments: %{conversation_id: m1.conversation_id}
      )

    assert Chat.unread_count(actor: ctx.user, tenant: ctx.ws.id) == 1

    # Advance my cursor to the latest message → no longer unread.
    parts =
      Chat.participants_for_conversation!(m1.conversation_id,
        actor: ctx.user,
        tenant: ctx.ws.id,
        load: [:membership]
      )

    mine =
      Enum.find(parts, fn p -> match?(%{membership: %{user_id: u}} when u == ctx.user.id, p) end)

    {:ok, _} =
      Chat.mark_participant_read(mine, %{last_read_message_id: m2.id},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    assert Chat.unread_count(actor: ctx.user, tenant: ctx.ws.id) == 0
  end

  test "unread_count is per-actor (cursors are private)", ctx do
    {:ok, other} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ucount-other#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^other.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, _} = Accounts.add_member(ctx.ws.id, to_string(other.email), actor: ctx.user)

    {:ok, _m} =
      Chat.create_message(%{text: "hi", addresses_host: false},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    # The author participates (cursor nil → unread for them); `other` is not a
    # participant of this conversation, so it is not in their unread set.
    assert Chat.unread_count(actor: ctx.user, tenant: ctx.ws.id) == 1
    assert Chat.unread_count(actor: other, tenant: ctx.ws.id) == 0
  end
end
