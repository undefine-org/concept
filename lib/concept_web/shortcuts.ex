defmodule ConceptWeb.Shortcuts do
  @moduledoc """
  Single source of truth for the app's keyboard shortcuts (E-3).

  The command-palette cheatsheet renders from `all/0` instead of hardcoding the
  list inline, so a shortcut is declared once and surfaced everywhere. The
  client dispatch lives in `assets/js/hooks/global_keys.js`; when adding a
  binding, add it here (for discovery) and there (for dispatch) — this registry
  is the authoritative *description* of what exists.

  Each entry:
    * `:keys`  — display tokens, already in render order (e.g. `["⌘", "K"]`)
    * `:label` — human description
    * `:scope` — `:global` (works anywhere) | `:editor` (in a page)
  """

  @type shortcut :: %{keys: [String.t()], label: String.t(), scope: :global | :editor}

  @shortcuts [
    %{keys: ["⌘", "K"], label: "Open the command palette", scope: :global},
    %{keys: ["⌘", "J"], label: "Toggle the chat panel", scope: :global},
    %{keys: ["/"], label: "Open the slash menu in the editor", scope: :editor},
    %{keys: ["Esc"], label: "Close any open panel", scope: :global}
  ]

  @doc "All registered shortcuts, in display order."
  @spec all :: [shortcut]
  def all, do: @shortcuts

  @doc "Shortcuts for a given scope."
  @spec for_scope(:global | :editor) :: [shortcut]
  def for_scope(scope), do: Enum.filter(@shortcuts, &(&1.scope == scope))
end
