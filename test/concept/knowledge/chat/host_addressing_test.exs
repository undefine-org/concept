defmodule Concept.Knowledge.Chat.HostAddressingTest do
  @moduledoc """
  Wave 0 (corrected): host addressing is POLYMORPHIC over `{host_type, host_id}`
  through the single `Message.:create` action. `use Concept.Hostable` is pure
  opt-in (registry + scope); there is NO per-host `discuss` action. One tool,
  every host — the parity-correct expression of the host model (PLAN-010).
  """
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Chat

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "host-addr-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Concept.Pages.create_page("Roadmap", workspace.id, nil, actor: user, tenant: workspace.id)

    %{user: user, workspace: workspace, page: page}
  end

  test "addressing a page host find-or-creates that page's conversation", ctx do
    %{user: user, workspace: ws, page: page} = ctx

    {:ok, _msg} =
      Chat.create_message(
        %{text: "Should offline mode ship in Q3?", host_type: :page, host_id: page.id},
        actor: user,
        tenant: ws.id
      )

    {:ok, [conversation]} =
      Chat.conversations_for_host(:page, page.id, actor: user, tenant: ws.id)

    assert conversation.host_type == :page
    assert conversation.host_id == page.id

    {:ok, messages} = Chat.message_history(conversation.id, actor: user, tenant: ws.id)
    assert Enum.any?(messages, &(&1.text == "Should offline mode ship in Q3?"))
  end

  test "a second message to the same page reuses its conversation", ctx do
    %{user: user, workspace: ws, page: page} = ctx

    send = fn text ->
      Chat.create_message!(%{text: text, host_type: :page, host_id: page.id},
        actor: user,
        tenant: ws.id
      )
    end

    send.("first")
    send.("second")

    {:ok, conversations} = Chat.conversations_for_host(:page, page.id, actor: user, tenant: ws.id)
    assert length(conversations) == 1
  end

  test "default host is :workspace (today's behaviour, unchanged)", ctx do
    %{user: user, workspace: ws} = ctx

    {:ok, msg} = Chat.create_message(%{text: "hello workspace"}, actor: user, tenant: ws.id)
    {:ok, conversation} = Chat.get_conversation(msg.conversation_id, actor: user, tenant: ws.id)

    assert conversation.host_type == :workspace
    assert conversation.host_id == nil
  end

  test "message_create is the single MCP tool that serves every host" do
    names = AshAi.Info.tools(Concept.Knowledge.Chat) |> Enum.map(& &1.name)

    assert :message_create in names
    # No per-host discuss tools — the host model is polymorphic over one action.
    refute :page_discuss in names
  end
end
