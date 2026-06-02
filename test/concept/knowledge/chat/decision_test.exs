defmodule Concept.Knowledge.Chat.DecisionTest do
  @moduledoc """
  T5 — conversation decisions: the :open/:decided lifecycle (PLAN-010 §20).
  decide marks the outcome settled; reopen restores it. A decided conversation
  is a first-class, searchable decision record.
  """
  use Concept.DataCase, async: false

  alias Concept.Knowledge.Chat
  alias Concept.Repo
  import Ecto.Query

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "decide#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, msg} =
      Chat.create_message(%{text: "decide me", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, user: user, ws: ws, conversation_id: msg.conversation_id}
  end

  test "a conversation starts open", ctx do
    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)
    assert conv.state == :open
  end

  test "decide -> decided, reopen -> open (round-trip)", ctx do
    conv = Chat.get_conversation!(ctx.conversation_id, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, decided} = Chat.decide_conversation(conv, %{}, actor: ctx.user, tenant: ctx.ws.id)
    assert decided.state == :decided

    {:ok, reopened} = Chat.reopen_conversation(decided, %{}, actor: ctx.user, tenant: ctx.ws.id)
    assert reopened.state == :open
  end
end
