defmodule Concept.Knowledge.BlockChunkerTest do
  @moduledoc """
  Regression suite for `Concept.Knowledge.BlockChunker`.

  BUG-056: `token_count` must be estimated once per chunk and carried
  through coalescing, never recomputed from `byte_size/1` downstream.
  """
  use ExUnit.Case, async: true

  alias Concept.Knowledge.BlockChunker

  defp content(text) do
    %{
      "root" => %{
        "children" => [
          %{"type" => "paragraph", "children" => [%{"type" => "text", "text" => text}]}
        ]
      }
    }
  end

  defp block(id, text) do
    %{
      id: id,
      type: :paragraph,
      parent_block_id: nil,
      position: id,
      content: content(text),
      props: %{}
    }
  end

  defp chunk(blocks) do
    BlockChunker.chunk("", blocks: blocks, page: %{id: "p1", title: "T"}, workspace_id: "w1")
  end

  describe "token_count (BUG-056)" do
    test "a single chunk's token_count is the grapheme-based estimate of its text" do
      [c] = chunk([block("b1", "Hello world this is a paragraph")])
      assert c.token_count == max(1, div(String.length(c.text), 4))
    end

    test "merged chunk token_count is the SUM of inputs, not a byte_size recompute" do
      # Two tiny blocks coalesce into one chunk. The merged count must equal
      # the sum of the per-chunk estimates (1 + 2 = 3), which differs from a
      # byte_size/4 recompute over the merged text.
      [merged] = chunk([block("b1", "Short"), block("b2", "Also short")])

      assert merged.text == "Short\n\nAlso short"
      assert merged.token_count == 3
      # Guard against regression to byte_size-of-merged-text (== 4 here).
      refute merged.token_count == max(1, div(byte_size(merged.text), 4))
    end

    test "token_count is always at least 1" do
      [c] = chunk([block("b1", "x")])
      assert c.token_count >= 1
    end
  end
end
