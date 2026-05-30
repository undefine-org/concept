defmodule Concept.Knowledge.Chat.ThreadTest do
  @moduledoc """
  Wave 3 (FEAT-077): a thread is a child conversation spawned from a message,
  inheriting the parent's host and linking back via parent/seed pointers
  (PLAN-010 §13). One self-referential resource, no separate Thread entity.
  """
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Chat

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "thread-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} = Concept.Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)

    # A root message hosted by the page.
    {:ok, root} =
      Chat.create_message(%{text: "should we ship offline mode?", host_type: :page, host_id: page.id},
        actor: user,
        tenant: ws.id
      )

    %{user: user, workspace: ws, page: page, root: root}
  end

  test "replying to a message spawns a child thread inheriting the host", ctx do
    %{user: u, workspace: ws, page: page, root: root} = ctx

    {:ok, reply} =
      Chat.create_message(%{text: "compare with competitors", reply_to_message_id: root.id},
        actor: u,
        tenant: ws.id
      )

    {:ok, thread} = Chat.get_conversation(reply.conversation_id, actor: u, tenant: ws.id)

    refute thread.id == root.conversation_id
    assert thread.parent_conversation_id == root.conversation_id
    assert thread.seed_message_id == root.id
    # host inherited from the parent
    assert thread.host_type == :page
    assert thread.host_id == page.id
  end

  test "replying twice to the same seed reuses the thread", ctx do
    %{user: u, workspace: ws, root: root} = ctx

    {:ok, r1} =
      Chat.create_message(%{text: "first", reply_to_message_id: root.id}, actor: u, tenant: ws.id)

    {:ok, r2} =
      Chat.create_message(%{text: "second", reply_to_message_id: root.id}, actor: u, tenant: ws.id)

    assert r1.conversation_id == r2.conversation_id

    {:ok, threads} = Chat.thread_for_seed(root.id, actor: u, tenant: ws.id)
    assert length(threads) == 1
  end
end
