defmodule ConceptWeb.Objects.RecordPicker do
  @moduledoc """
  A reusable overlay for picking a `Record` by title — the human surface of the
  **non-redundancy seam** (docs/objects_and_tasks.md §2). A `record_ref` block
  uses it to choose the one canonical record it projects; the same component
  can later serve `:relation` field pickers.

  Pure component: it renders a search box + result rows and emits the host's
  event names (`on_search`, `on_select`, `on_close`). The host LiveView owns
  the transient query/results state and runs `Concept.Objects.search_records/1`
  — so this component does no data access (and the host stays EX9001-pure via
  the code interface).
  """
  use ConceptWeb, :html

  attr :results, :list, default: []
  attr :query, :string, default: ""
  attr :on_search, :string, required: true
  attr :on_select, :string, required: true
  attr :on_close, :string, required: true

  def record_picker(assigns) do
    ~H"""
    <div id="record-picker" class="fixed inset-0 z-50 flex items-start justify-center pt-24">
      <div class="absolute inset-0 bg-black/20" phx-click={@on_close} />

      <div class="relative w-full max-w-md rounded-lg border border-notion-divider bg-white shadow-xl">
        <form phx-change={@on_search} class="border-b border-notion-divider p-3">
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search records by title…"
            autocomplete="off"
            phx-debounce="150"
            class="w-full rounded-md border border-notion-divider px-3 py-1.5 text-sm focus:border-notion-text focus:outline-none"
          />
        </form>

        <ul id="record-picker-results" class="max-h-72 overflow-y-auto py-1">
          <li
            :for={r <- @results}
            id={"picker-#{r.id}"}
            phx-click={@on_select}
            phx-value-record={r.id}
            class="flex cursor-pointer items-center justify-between px-3 py-2 text-sm hover:bg-notion-gray"
          >
            <span class="font-medium text-notion-text">{record_title(r)}</span>
            <span class="text-xs text-notion-text-light">{type_name(r)}</span>
          </li>
          <li :if={@results == []} class="px-3 py-4 text-center text-sm text-notion-text-light">
            No matching records
          </li>
        </ul>

        <div class="flex justify-end border-t border-notion-divider px-3 py-2">
          <button
            type="button"
            phx-click={@on_close}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp record_title(%{title: t}) when is_binary(t) and t != "", do: t
  defp record_title(_), do: "Untitled"

  defp type_name(%{object_type: %{name: n}}) when is_binary(n), do: n
  defp type_name(_), do: ""
end
