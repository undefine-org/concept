defmodule Concept.Knowledge.Chat.ReactionTest do
  @moduledoc """
  T4 — the Reaction resource: an identity-keyed join (membership × message ×
  emoji), the structural twin of Participant. react is idempotent (upsert),
  unreact removes, and reads list per message / conversation.
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
        email: "react#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, membership} = Accounts.get_membership(user.id, ws.id, actor: user)

    {:ok, msg} =
      Chat.create_message(%{text: "react to me", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, user: user, ws: ws, membership: membership, msg: msg}
  end

  defp react(ctx, emoji) do
    Chat.react(
      %{
        workspace_id: ctx.ws.id,
        message_id: ctx.msg.id,
        membership_id: ctx.membership.id,
        emoji: emoji
      },
      actor: ctx.user,
      tenant: ctx.ws.id
    )
  end

  test "react adds a reaction", ctx do
    assert {:ok, reaction} = react(ctx, "👍")
    assert reaction.emoji == "👍"
    assert reaction.message_id == ctx.msg.id

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert length(reactions) == 1
  end

  test "re-reacting with the same emoji is idempotent (upsert)", ctx do
    {:ok, _} = react(ctx, "👍")
    {:ok, _} = react(ctx, "👍")

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert length(reactions) == 1
  end

  test "different emoji from the same member are distinct reactions", ctx do
    {:ok, _} = react(ctx, "👍")
    {:ok, _} = react(ctx, "🎉")

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert length(reactions) == 2
  end

  test "unreact removes a reaction", ctx do
    {:ok, reaction} = react(ctx, "👍")
    :ok = Chat.unreact(reaction, actor: ctx.user, tenant: ctx.ws.id)

    reactions =
      Chat.reactions_for_message!(ctx.msg.id, actor: ctx.user, tenant: ctx.ws.id)

    assert reactions == []
  end

  test "reactions_for_conversation lists reactions across the conversation", ctx do
    {:ok, _} = react(ctx, "🚀")

    reactions =
      Chat.reactions_for_conversation!(ctx.msg.conversation_id,
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    assert length(reactions) == 1
  end
end
