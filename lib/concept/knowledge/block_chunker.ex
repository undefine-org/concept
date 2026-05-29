defmodule Concept.Knowledge.BlockChunker do
  @moduledoc """
  Custom Arcana chunker that mirrors Concept's block tree.
  Each top-level block becomes one chunk with metadata pointing to its block_id.
  Tiny sibling blocks are coalesced up to a token threshold.
  """
  @behaviour Arcana.Chunker

  @target_tokens 512
  @merge_below 128

  @impl true
  def chunk(_ignored, opts) do
    blocks = Keyword.fetch!(opts, :blocks)
    page = Keyword.fetch!(opts, :page)
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    breadcrumbs = Keyword.get(opts, :breadcrumbs, page.title || "Untitled")

    tree = build_tree(blocks)

    tree
    |> Enum.map(&render_block/1)
    |> Enum.reject(&(String.trim(&1.text) == ""))
    |> coalesce_small()
    |> Enum.with_index()
    |> Enum.map(fn {%{text: t, block_ids: ids, primary_id: pid, type: type, token_count: tc},
                    idx} ->
      %{
        text: t,
        chunk_index: idx,
        token_count: tc,
        metadata: %{
          "page_id" => page.id,
          "workspace_id" => workspace_id,
          "block_id" => pid,
          "block_ids" => ids,
          "block_type" => to_string(type),
          "breadcrumbs" => breadcrumbs
        }
      }
    end)
  end

  # Build a tree from flat block list: group by parent_block_id
  defp build_tree(blocks) do
    blocks_map = Map.new(blocks, &{&1.id, &1})

    blocks
    |> Enum.group_by(& &1.parent_block_id)
    |> then(fn groups ->
      # Start with top-level blocks (parent_block_id == nil)
      children_of(nil, groups, blocks_map)
    end)
  end

  defp children_of(parent_id, groups, blocks_map) do
    Map.get(groups, parent_id, [])
    |> Enum.sort_by(&(&1.position || ""))
    |> Enum.map(fn block ->
      {block, children_of(block.id, groups, blocks_map)}
    end)
  end

  # Render a block node to markdown text
  defp render_block({block, children}) do
    md = Concept.Lexical.to_markdown(block.content || %{})
    type = block.type

    prefix = block_prefix(type, block)
    child_text = render_children(children, type)

    text =
      cond do
        type in [:divider] -> "---"
        type in [:columns, :column] -> md <> child_text
        type in [:bulleted_list_item, :numbered_list_item, :to_do] -> prefix <> md <> child_text
        child_text != "" -> prefix <> md <> "\n" <> child_text
        true -> prefix <> md
      end

    trimmed = String.trim(text)

    %{
      text: trimmed,
      block_ids: [block.id] ++ collect_child_ids(children),
      primary_id: block.id,
      type: type,
      # Estimate tokens once, here. Carried through coalescing so it is never
      # recomputed from byte_size downstream (BUG-056).
      token_count: estimate_tokens(trimmed)
    }
  end

  # Single source of the token estimate. byte_size/4 over-counts multibyte
  # text; String.length (graphemes) is a closer, language-stable proxy.
  defp estimate_tokens(text), do: max(1, div(String.length(text), 4))

  defp block_prefix(:heading_1, _), do: "# "
  defp block_prefix(:heading_2, _), do: "## "
  defp block_prefix(:heading_3, _), do: "### "
  defp block_prefix(:quote, _), do: "> "
  defp block_prefix(:bulleted_list_item, _), do: "- "

  defp block_prefix(:numbered_list_item, block) do
    index = Map.get(block.props || %{}, "number", 1)
    "#{index}. "
  end

  defp block_prefix(:to_do, block) do
    checked = Map.get(block.props || %{}, "checked", false)
    if checked, do: "- [x] ", else: "- [ ] "
  end

  defp block_prefix(:callout, _), do: "> "
  defp block_prefix(:toggle, _), do: ""

  defp block_prefix(:code, block) do
    lang = Map.get(block.props || %{}, "language", "")
    if lang != "", do: "```#{lang}\n", else: "```\n"
  end

  defp block_prefix(_, _), do: ""

  defp render_children(children, parent_type) do
    rendered =
      children
      |> Enum.map(&render_block/1)
      |> Enum.reject(&(String.trim(&1.text) == ""))
      |> Enum.map(
        &if parent_type == :code, do: &1.text, else: String.replace(&1.text, "\n", "\n  ")
      )

    if rendered == [], do: "", else: Enum.join(rendered, "\n")
  end

  defp collect_child_ids([]), do: []

  defp collect_child_ids(children) do
    Enum.flat_map(children, fn {block, sub_children} ->
      [block.id | collect_child_ids(sub_children)]
    end)
  end

  # Coalesce small siblings to reduce chunk count
  defp coalesce_small(chunks, acc \\ [])
  defp coalesce_small([], acc), do: Enum.reverse(acc)

  defp coalesce_small([chunk | rest], []) do
    coalesce_small(rest, [chunk])
  end

  defp coalesce_small([chunk | rest], [prev | prev_rest]) do
    prev_tokens = prev.token_count
    curr_tokens = chunk.token_count

    if prev_tokens + curr_tokens <= @target_tokens and curr_tokens < @merge_below do
      merged = %{
        prev
        | text: prev.text <> "\n\n" <> chunk.text,
          block_ids: prev.block_ids ++ chunk.block_ids,
          token_count: prev_tokens + curr_tokens
      }

      coalesce_small(rest, [merged | prev_rest])
    else
      coalesce_small(rest, [chunk, prev | prev_rest])
    end
  end
end
