defmodule Concept.Knowledge.Chat.Reactors.Steps.CloneBlocks do
  @moduledoc """
  Crystallize step: clone every block of a conversation's messages onto the
  target page (preserving hierarchy + order), author provenance links, and mark
  the conversation crystallized.

  Runs under a system actor (`authorize?: false`) inside the crystallize action,
  whose own policy gates who may invoke it.

  Guarantees:
  - **Idempotent**: if the conversation is already crystallized, this is a no-op
    (returns the previously-cloned page's block ids would require tracking, so we
    simply return `[]` and leave the existing page untouched).
  - **Atomic**: the whole clone + link + mark runs in one `Repo.transaction`, so
    a mid-loop failure rolls back — no half-crystallized page, no orphan links.
  - **Structure-preserving**: parents are cloned before children and an
    old→new id map rewires `parent_block_id`, so the page mirrors the
    conversation's block hierarchy.
  """
  use Reactor.Step

  require Ash.Query

  @impl true
  def run(
        %{conversation_id: conversation_id, target_page_id: page_id, workspace_id: workspace_id},
        _context,
        _opts
      ) do
    opts = [actor: %{system?: true}, authorize?: false, tenant: workspace_id]

    {:ok, conversation} = Concept.Knowledge.Chat.get_conversation(conversation_id, opts)

    cond do
      # Idempotency guard (BUG-068): never crystallize twice.
      not is_nil(conversation.crystallized_page_id) ->
        {:ok, []}

      true ->
        do_crystallize(conversation, page_id, workspace_id, opts)
    end
  rescue
    e -> {:error, e}
  end

  defp do_crystallize(conversation, page_id, workspace_id, opts) do
    source_blocks = conversation_blocks(conversation.id, workspace_id)

    # Atomic (BUG-068): all-or-nothing. Ash actions create their own inner
    # transactions + notifications; wrapping with `Ash.transaction/3` (not a raw
    # Repo.transaction, which trips Ash's missed-notifications guard) gives a
    # single rolled-back unit while letting Ash flush notifications on commit.
    Ash.transaction([Concept.Pages.Block, Concept.Knowledge.Chat.Conversation], fn ->
      # Parents before children so the id map is populated when a child clones
      # (BUG-067): nil-parent blocks first, then by position.
      ordered = Enum.sort_by(source_blocks, &{not is_nil(&1.parent_block_id), &1.position})

      {cloned_ids, _id_map} =
        Enum.reduce(ordered, {[], %{}}, fn block, {ids, id_map} ->
          new_parent_id = block.parent_block_id && Map.get(id_map, block.parent_block_id)
          {:ok, new_block} = clone_block(block, page_id, new_parent_id, workspace_id, opts)
          link_provenance(block, new_block, workspace_id, opts)
          {[new_block.id | ids], Map.put(id_map, block.id, new_block.id)}
        end)

      mark_crystallized(conversation, page_id, opts)
      Enum.reverse(cloned_ids)
    end)
  end

  # All non-archived blocks across the conversation's messages, in
  # (message inserted_at, parent, position) order.
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

  defp clone_block(block, page_id, new_parent_id, workspace_id, opts) do
    attrs = %{
      container_type: :page,
      container_id: page_id,
      parent_block_id: new_parent_id,
      type: block.type,
      content: block.content || %{},
      props: block.props || %{},
      workspace_id: workspace_id
    }

    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, attrs, opts)
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

  defp mark_crystallized(conversation, page_id, opts) do
    Concept.Knowledge.Chat.mark_crystallized(conversation, %{crystallized_page_id: page_id}, opts)
  end
end
