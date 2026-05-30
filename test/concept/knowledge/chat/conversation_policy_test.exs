defmodule Concept.Knowledge.Chat.ConversationPolicyTest do
  @moduledoc """
  Wave 1 (FEAT-076): Conversation gains real policies. Today's ACL is binary
  (any workspace member sees all conversations); the participant clause makes
  private conversations possible later. A non-member must not read another
  workspace's conversation.
  """
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Chat

  defp register(email_prefix) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{email_prefix}-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {user, workspace}
  end

  test "a workspace member can read conversations in their workspace" do
    {user, ws} = register("conv-pol-member")

    {:ok, conv} =
      Chat.create_conversation(%{workspace_id: ws.id}, actor: user, tenant: ws.id)

    assert {:ok, _} = Chat.get_conversation(conv.id, actor: user, tenant: ws.id)
  end

  test "a non-member (another workspace's user) cannot read the conversation" do
    {owner, ws} = register("conv-pol-owner")
    {outsider, _other_ws} = register("conv-pol-outsider")

    {:ok, conv} =
      Chat.create_conversation(%{workspace_id: ws.id}, actor: owner, tenant: ws.id)

    # Even forcing the tenant, the policy denies a non-member: get returns nil.
    assert {:error, _} = Chat.get_conversation(conv.id, actor: outsider, tenant: ws.id)
  end
end
