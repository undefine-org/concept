defmodule Concept.Knowledge.Chat.BudgetTest do
  @moduledoc """
  Wave 4 (FEAT-078): the agent-turn budget bounds automatic host/agent turns.
  needs_host_response is false once the budget is exhausted; a human post
  replenishes it (PLAN-010 §B). One integer caps runaway agent↔agent loops.
  """
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Chat

  defp register(prefix) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {user, ws}
  end

  test "a new conversation starts with the default budget" do
    {u, ws} = register("budget")
    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: u, tenant: ws.id)
    assert conv.agent_turn_budget == 5
  end

  test "decrement floors at zero and then needs_host_response is false" do
    {u, ws} = register("budget")
    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: u, tenant: ws.id)

    conv =
      Enum.reduce(1..6, conv, fn _i, c ->
        {:ok, c} = Chat.decrement_budget(c, actor: u, tenant: ws.id)
        c
      end)

    assert conv.agent_turn_budget == 0

    # A host-addressed message owes NO response once the budget is spent.
    {:ok, msg} =
      Chat.create_message(%{text: "@host?", conversation_id: conv.id, addresses_host: true},
        actor: u,
        tenant: ws.id
      )

    {:ok, loaded} = Ash.load(msg, [:needs_host_response], actor: u, tenant: ws.id)
    refute loaded.needs_host_response
  end

  test "replenish restores the budget to the default" do
    {u, ws} = register("budget")
    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: u, tenant: ws.id)
    {:ok, conv} = Chat.decrement_budget(conv, actor: u, tenant: ws.id)
    {:ok, conv} = Chat.decrement_budget(conv, actor: u, tenant: ws.id)
    assert conv.agent_turn_budget == 3

    {:ok, conv} = Chat.replenish_budget(conv, actor: u, tenant: ws.id)
    assert conv.agent_turn_budget == 5
  end

  test "a human posting replenishes a depleted conversation" do
    {u, ws} = register("budget")
    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: u, tenant: ws.id)

    conv =
      Enum.reduce(1..5, conv, fn _i, c ->
        {:ok, c} = Chat.decrement_budget(c, actor: u, tenant: ws.id)
        c
      end)

    assert conv.agent_turn_budget == 0

    {:ok, _msg} =
      Chat.create_message(%{text: "back to it", conversation_id: conv.id, addresses_host: false},
        actor: u,
        tenant: ws.id
      )

    {:ok, reloaded} = Chat.get_conversation(conv.id, actor: u, tenant: ws.id)
    assert reloaded.agent_turn_budget == 5
  end
end
