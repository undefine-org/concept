defmodule Concept.Pages.BlockContainerTest do
  @moduledoc """
  The content-layer membrane, post-Container-cutover. A Block lives in exactly
  one polymorphic container — `container_type` (registry-validated) +
  `container_id` — replacing the former page_id-XOR-message_id pair. These cases
  are the regression floor: a page block, a message block, and the not-null
  cardinality that used to be a check constraint.
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

    {:ok, msg} =
      Chat.create_message(%{text: "see table", addresses_host: false}, actor: user, tenant: ws.id)

    %{user: user, workspace: ws, conversation: conv, message: msg}
  end

  test "a message can contain blocks (the membrane dissolves at content)", ctx do
    %{user: u, workspace: ws, message: msg} = ctx

    {:ok, block} =
      Pages.Block
      |> Ash.Changeset.for_create(
        :create_block,
        %{
          container_type: :message,
          container_id: msg.id,
          type: :paragraph,
          content: %{},
          workspace_id: ws.id
        },
        actor: u,
        tenant: ws.id
      )
      |> Ash.create()

    assert block.container_type == :message
    assert block.container_id == msg.id

    {:ok, loaded} = Ash.load(msg, [:blocks], actor: u, tenant: ws.id)
    # The message auto-mirrors its text into a block on send (T6), so the body
    # contains that mirror PLUS this explicitly-added block. Assert membership,
    # not exclusivity.
    assert block.id in Enum.map(loaded.blocks, & &1.id)
  end

  test "a block with NO container is rejected (container_type/id are not-null)", ctx do
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

  test "an unregistered container_type is rejected by the TypeAttr", ctx do
    %{user: u, workspace: ws} = ctx

    assert {:error, _} =
             Pages.Block
             |> Ash.Changeset.for_create(
               :create_block,
               %{
                 container_type: :workspace,
                 container_id: Ash.UUID.generate(),
                 type: :paragraph,
                 content: %{},
                 workspace_id: ws.id
               },
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
        %{
          container_type: :page,
          container_id: page.id,
          type: :paragraph,
          content: %{},
          workspace_id: ws.id
        },
        actor: u,
        tenant: ws.id
      )
      |> Ash.create()

    assert block.container_type == :page
    assert block.container_id == page.id

    {:ok, loaded} = Ash.load(page, [:blocks], actor: u, tenant: ws.id)
    assert Enum.map(loaded.blocks, & &1.id) == [block.id]
  end

  test "list_for_page returns only page-container blocks; list_for_message only message ones",
       ctx do
    %{user: u, workspace: ws, message: msg} = ctx
    {:ok, page} = Pages.create_page("Doc", ws.id, nil, actor: u, tenant: ws.id)

    # The message already has its T6 auto-mirrored block; record it so the
    # container-isolation assertion accounts for it.
    {:ok, premirrored} = Pages.list_for_message(msg.id, actor: u, tenant: ws.id)
    premirrored_ids = Enum.map(premirrored, & &1.id)

    {:ok, pblock} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: u, tenant: ws.id)

    {:ok, mblock} =
      Pages.create_block(:message, msg.id, :paragraph, ws.id, nil, actor: u, tenant: ws.id)

    {:ok, page_blocks} = Pages.list_for_page(page.id, actor: u, tenant: ws.id)
    {:ok, msg_blocks} = Pages.list_for_message(msg.id, actor: u, tenant: ws.id)

    # The page block list is exactly [pblock] (page bodies aren't auto-mirrored).
    assert Enum.map(page_blocks, & &1.id) == [pblock.id]
    # The message list is the auto-mirrored block(s) PLUS the explicit mblock,
    # and contains NO page block (container isolation).
    msg_ids = Enum.map(msg_blocks, & &1.id)
    assert mblock.id in msg_ids
    assert Enum.sort(msg_ids) == Enum.sort([mblock.id | premirrored_ids])
    refute pblock.id in msg_ids
  end

  test "destroying a message cascades to its blocks (replaces the dropped FK)", ctx do
    %{user: u, workspace: ws} = ctx

    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: u, tenant: ws.id)

    {:ok, msg} =
      Chat.create_message(%{text: "doomed", addresses_host: false}, actor: u, tenant: ws.id)

    {:ok, block} =
      Pages.create_block(:message, msg.id, :paragraph, ws.id, nil, actor: u, tenant: ws.id)

    :ok = Ash.destroy!(msg, actor: u, tenant: ws.id)

    # The block is gone (hard-deleted by the cascade), not merely archived.
    assert {:error, _} =
             Ash.get(Pages.Block, block.id, actor: u, tenant: ws.id, authorize?: false)

    _ = conv
  end
end
