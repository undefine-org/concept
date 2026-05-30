defmodule Concept.Knowledge.Chat.InboxTest do
  @moduledoc """
  Wave 4b (FEAT-078): the inbox projection (conversations the actor participates
  in) and the recipient-keyed PubSub fan-out inbox:<user_id> (PLAN-010 §A).
  """
  use Concept.DataCase, async: true
  require Ash.Query

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

  test "inbox lists conversations the actor participates in" do
    {u, ws} = register("inbox")

    # Sending a message auto-joins the sender as a participant.
    {:ok, _m} = Chat.create_message(%{text: "hi", addresses_host: false}, actor: u, tenant: ws.id)

    {:ok, inbox} = Chat.inbox(actor: u, tenant: ws.id)
    assert length(inbox) >= 1
  end

  test "inbox excludes conversations the actor does not participate in" do
    {owner, ws} = register("inbox-owner")
    {outsider, _} = register("inbox-outsider")

    {:ok, _m} =
      Chat.create_message(%{text: "private", addresses_host: false}, actor: owner, tenant: ws.id)

    # Outsider is not a member of this workspace → empty inbox there.
    {:ok, inbox} = Chat.inbox(actor: outsider, tenant: ws.id)
    assert inbox == []
  end

  test "creating a message broadcasts inbox activity to participant's topic" do
    {u, ws} = register("inbox-bcast")

    # Seed a page-hosted conversation + participant (first message).
    {:ok, page} = Concept.Pages.create_page("P", ws.id, nil, actor: u, tenant: ws.id)

    {:ok, m1} =
      Chat.create_message(
        %{text: "one", host_type: :page, host_id: page.id, addresses_host: false},
        actor: u,
        tenant: ws.id
      )

    # Subscribe to this user's inbox, then post again into the same conversation.
    Phoenix.PubSub.subscribe(Concept.PubSub, "inbox:#{u.id}")

    {:ok, _m2} =
      Chat.create_message(
        %{text: "two", host_type: :page, host_id: page.id, addresses_host: false},
        actor: u,
        tenant: ws.id
      )

    assert_receive {:inbox_activity, %{conversation_id: conv_id}}, 1000
    assert conv_id == m1.conversation_id
  end
end
