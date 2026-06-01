defmodule ConceptWeb.ShortcutsTest do
  @moduledoc "E-3: the keyboard-shortcut registry is the single source of truth."
  use ExUnit.Case, async: true

  alias ConceptWeb.Shortcuts

  test "all/0 returns shortcuts with keys, label, and scope" do
    for sc <- Shortcuts.all() do
      assert is_list(sc.keys) and sc.keys != []
      assert is_binary(sc.label)
      assert sc.scope in [:global, :editor]
    end
  end

  test "the core bindings are registered" do
    labels = Shortcuts.all() |> Enum.map(& &1.label) |> Enum.join(" ")
    assert labels =~ "command palette"
    assert labels =~ "chat"
    assert labels =~ "slash menu"
  end

  test "for_scope/1 filters by scope" do
    assert Enum.all?(Shortcuts.for_scope(:editor), &(&1.scope == :editor))
    assert Shortcuts.for_scope(:global) != []
  end
end
