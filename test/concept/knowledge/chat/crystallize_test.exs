defmodule Concept.Knowledge.Chat.CrystallizeTest do
  @moduledoc """
  Wave 5 (FEAT-079): crystallize a conversation into a durable page — talk
  becomes document (PLAN-010 §20, §46). COPY semantics: message blocks are
  cloned onto the page with provenance links; the conversation is marked
  crystallized and its scrollback stays intact.
  """
  use Concept.DataCase, async: true
  require Ash.Query

  alias Concept.Knowledge.Chat
  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "crystallize-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Target", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conv} = Chat.create_conversation(%{workspace_id: ws.id}, actor: user, tenant: ws.id)

    {:ok, msg} =
      Chat.create_message(%{text: "decision", addresses_host: false}, actor: user, tenant: ws.id)

    {:ok, src_block} =
      Pages.Block
      |> Ash.Changeset.for_create(
        :create_block,
        %{
          message_id: msg.id,
          type: :paragraph,
          content: %{"text" => "ship it"},
          workspace_id: ws.id
        },
        actor: user,
        tenant: ws.id
      )
      |> Ash.create()

    %{
      user: user,
      workspace: ws,
      page: page,
      conversation: msg.conversation_id,
      src_block: src_block
    }
  end

  test "crystallize clones message blocks onto the page and marks the conversation", ctx do
    %{user: u, workspace: ws, page: page, conversation: conv_id, src_block: src} = ctx

    {:ok, _cloned} =
      Chat.crystallize_conversation(conv_id, page.id, ws.id, actor: u, tenant: ws.id)

    # Page now has a cloned block with the same content.
    {:ok, page_blocks} = Pages.list_for_page(page.id, actor: u, tenant: ws.id)
    assert Enum.any?(page_blocks, &(&1.content["text"] == "ship it"))

    # Conversation is marked crystallized into the page.
    {:ok, conv} = Chat.get_conversation(conv_id, actor: u, tenant: ws.id)
    assert conv.crystallized_page_id == page.id

    # Source message block is untouched (copy, not move).
    {:ok, reloaded_src} = Ash.get(Pages.Block, src.id, actor: u, tenant: ws.id)
    assert reloaded_src.message_id != nil
  end

  test "crystallize authors provenance links from source to cloned blocks", ctx do
    %{user: u, workspace: ws, page: page, conversation: conv_id, src_block: src} = ctx

    {:ok, _} = Chat.crystallize_conversation(conv_id, page.id, ws.id, actor: u, tenant: ws.id)

    {:ok, links} =
      Concept.Knowledge.Link
      |> Ash.Query.filter(source_block_id == ^src.id and kind == :crystallized_from)
      |> Ash.read(actor: u, tenant: ws.id)

    assert length(links) == 1
  end
end
