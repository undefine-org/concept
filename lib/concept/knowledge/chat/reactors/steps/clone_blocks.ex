defmodule Concept.Knowledge.Chat.Reactors.Steps.CloneBlocks do
  @moduledoc """
  Crystallize step: clone every block of a conversation's messages onto the
  target page, author provenance links, and mark the conversation crystallized.

  Runs under a system actor (`authorize?: false`) inside the crystallize action,
  whose own policy gates who may invoke it. Order is preserved: messages oldest
  first, blocks in render order, so the page tail reflects conversation order.
  """
  use Reactor.Step

  require Ash.Query

  @impl true
  def run(
        %{conversation_id: conversation_id, target_page_id: page_id, workspace_id: workspace_id},
        _context,
        _opts
      ) do
    opts = [authorize?: false, tenant: workspace_id]

    source_blocks = conversation_blocks(conversation_id, workspace_id)

    cloned_ids =
      Enum.map(source_blocks, fn block ->
        {:ok, new_block} = clone_block(block, page_id, workspace_id, opts)
        link_provenance(block, new_block, workspace_id, opts)
        new_block.id
      end)

    mark_crystallized(conversation_id, page_id, opts)

    {:ok, cloned_ids}
  rescue
    e -> {:error, e}
  end

  # All non-archived blocks across the conversation's messages, in
  # (message inserted_at, block render order) order.
  defp conversation_blocks(conversation_id, workspace_id) do
    {:ok, messages} =
      Concept.Knowledge.Chat.Message
      |> Ash.Query.filter(conversation_id == ^conversation_id)
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read(authorize?: false, tenant: workspace_id)

    Enum.flat_map(messages, fn message ->
      case Concept.Pages.list_for_message(message.id, authorize?: false, tenant: workspace_id) do
        {:ok, blocks} -> blocks
        _ -> []
      end
    end)
  end

  defp clone_block(block, page_id, workspace_id, opts) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(
      :create_block,
      %{
        page_id: page_id,
        type: block.type,
        content: block.content || %{},
        props: block.props || %{},
        workspace_id: workspace_id
      },
      opts
    )
    |> Ash.create(opts)
  end

  defp link_provenance(source_block, new_block, workspace_id, opts) do
    Concept.Knowledge.create_link(
      %{
        source_block_id: source_block.id,
        target_block_id: new_block.id,
        kind: :crystallized_from,
        workspace_id: workspace_id
      },
      opts
    )
  end

  defp mark_crystallized(conversation_id, page_id, opts) do
    {:ok, conversation} =
      Concept.Knowledge.Chat.get_conversation(conversation_id, opts)

    Concept.Knowledge.Chat.mark_crystallized(conversation, %{crystallized_page_id: page_id}, opts)
  end
end
