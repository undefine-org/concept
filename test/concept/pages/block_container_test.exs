defmodule Concept.Pages.BlockContainerTest do
  @moduledoc """
  Wave 2 (FEAT-075): the content-layer membrane. A Block belongs to a page XOR a
  message (PLAN-010 §27-28). Messages contain blocks, so talk carries the
  editor's full block expressiveness; crystallization later reparents these onto
  the host page.
  """
  use Concept.DataCase, async: true
  require Ash.Query

  alias Concept.Knowledge.Chat
  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "block-container-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: user, tenant: ws.id)
    {:ok, msg} = Chat.create_message(%{text: "see table", addresses_host: false}, actor: user, tenant: ws.id)

    %{user: user, workspace: ws, conversation: conv, message: msg}
  end

  test "a message can contain blocks (the membrane dissolves at content)", ctx do
    %{user: u, workspace: ws, message: msg} = ctx

    {:ok, block} =
      Pages.Block
      |> Ash.Changeset.for_create(
        :create_block,
        %{message_id: msg.id, type: :paragraph, content: %{}, workspace_id: ws.id},
        actor: u,
        tenant: ws.id
      )
      |> Ash.create()

    assert block.message_id == msg.id
    assert is_nil(block.page_id)

    {:ok, loaded} = Ash.load(msg, [:blocks], actor: u, tenant: ws.id)
    assert Enum.map(loaded.blocks, & &1.id) == [block.id]
  end

  test "a block with NEITHER container is rejected by the check constraint", ctx do
    %{user: u, workspace: ws} = ctx

    assert {:error, _} =
             Pages.Block
             |> Ash.Changeset.for_create(
               :create_block,
               %{type: :paragraph, content: %{}, workspace_id: ws.id},
               actor: u,
               tenant: ws.id
             )
             |> Ash.create()
  end

  test "a block with BOTH containers is rejected by the check constraint", ctx do
    %{user: u, workspace: ws, message: msg} = ctx

    {:ok, page} = Pages.create_page("Doc", ws.id, nil, actor: u, tenant: ws.id)

    assert {:error, _} =
             Pages.Block
             |> Ash.Changeset.for_create(
               :create_block,
               %{page_id: page.id, message_id: msg.id, type: :paragraph, content: %{}, workspace_id: ws.id},
               actor: u,
               tenant: ws.id
             )
             |> Ash.create()
  end

  test "page-owned blocks still work unchanged (no regression)", ctx do
    %{user: u, workspace: ws} = ctx

    {:ok, page} = Pages.create_page("Doc", ws.id, nil, actor: u, tenant: ws.id)

    {:ok, block} =
      Pages.Block
      |> Ash.Changeset.for_create(
        :create_block,
        %{page_id: page.id, type: :paragraph, content: %{}, workspace_id: ws.id},
        actor: u,
        tenant: ws.id
      )
      |> Ash.create()

    assert block.page_id == page.id
    assert is_nil(block.message_id)
  end
end
