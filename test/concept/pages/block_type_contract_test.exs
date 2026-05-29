defmodule Concept.Pages.BlockTypeContractTest do
  @moduledoc """
  Structural contract for the block-type registry. These assertions are the
  permanent guard against the fractures the cutover fixed:

    * S1 — text presentation metadata lives on the type module, not in a
      `BlockRender` lookup table.
    * S2 — the slash menu the client renders is derived from the registry
      (incl. keywords), so the Elixir source of truth and the JS menu can
      never drift.
    * S3 — composite layout is declared per-type, not string-matched in the
      dispatcher.
    * S4 — every type advertises a `render_kind/0` the dispatcher understands.
  """
  use ExUnit.Case, async: true

  alias Concept.Pages.BlockTypes

  @kinds [:text, :static, :interactive, :composite]

  test "every registered type declares a known render_kind/0" do
    for mod <- BlockTypes.all() do
      assert mod.render_kind() in @kinds,
             "#{inspect(mod)} render_kind/0 = #{inspect(mod.render_kind())} not in #{inspect(@kinds)}"
    end
  end

  test "text types supply presentation metadata (S1)" do
    text_mods = Enum.filter(BlockTypes.all(), &(&1.render_kind() == :text))
    assert text_mods != [], "expected at least one text block type"

    for mod <- text_mods do
      assert is_binary(mod.placeholder()),
             "#{inspect(mod)} must define placeholder/0 returning a string"

      assert is_binary(mod.editor_class()) and mod.editor_class() != "",
             "#{inspect(mod)} must define editor_class/0 returning a non-empty string"
    end
  end

  test "composite types declare a layout the dispatcher handles (S3)" do
    for mod <- Enum.filter(BlockTypes.all(), &(&1.render_kind() == :composite)) do
      assert mod.composite_layout() in [:table, :columns],
             "#{inspect(mod)} composite_layout/0 must be :table or :columns"
    end
  end

  test "static types define render/1 (S4 — enforced at compile time, asserted here)" do
    for mod <- Enum.filter(BlockTypes.all(), &(&1.render_kind() == :static)) do
      assert function_exported?(mod, :render, 1),
             "#{inspect(mod)} (static) must export render/1"
    end
  end

  describe "slash menu registry feed (S2)" do
    test "slash_menu_items/0 is JSON-encodable with the keys the client reads" do
      items = BlockTypes.slash_menu_items()
      assert items != []

      for item <- items do
        assert Map.has_key?(item, :type)
        assert Map.has_key?(item, :label)
        assert Map.has_key?(item, :icon)
        assert Map.has_key?(item, :keywords)
        assert is_list(item.keywords)
        refute item.group == :hidden
      end

      # Must serialize cleanly — this is exactly what page_editor_live.ex feeds
      # into `<ora-slash-menu items={...}>`.
      assert {:ok, _json} = Jason.encode(items)
    end

    test "keyword affordances survive into the feed (e.g. /task → to_do)" do
      items = BlockTypes.slash_menu_items()
      todo = Enum.find(items, &(&1.type == :to_do))

      assert todo, "to_do should appear in the slash menu"

      assert "task" in todo.keywords,
             "to_do keywords must include 'task' so /task matches it client-side"
    end

    test "every non-hidden registered type appears exactly once in the feed" do
      items = BlockTypes.slash_menu_items()
      feed_types = items |> Enum.map(& &1.type) |> Enum.sort()

      expected =
        BlockTypes.all()
        |> Enum.reject(&(&1.slash_menu().group == :hidden))
        |> Enum.map(& &1.type())
        |> Enum.sort()

      assert feed_types == expected
      assert length(feed_types) == length(Enum.uniq(feed_types)), "no duplicate types in feed"
    end
  end
end
