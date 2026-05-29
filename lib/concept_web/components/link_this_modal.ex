defmodule ConceptWeb.Components.LinkThisModal do
  @moduledoc """
  Modal for creating knowledge graph links between blocks.

  Renders a dialog with kind selector and optional note input.
  Dispatches events back to parent LiveView for submission.
  """
  use Phoenix.Component
  import ConceptWeb.CoreComponents

  @doc """
  Renders a modal for creating a block-to-block link.

  ## Examples

      <.link_this_modal
        show={@link_modal_state != nil}
        source_block_id={@link_modal_state.source_block_id}
        target_block_id={@link_modal_state.target_block_id}
        error={@link_modal_state.error}
      />
  """
  attr :show, :boolean, required: true
  attr :source_block_id, :string, default: nil
  attr :target_block_id, :string, default: nil
  attr :error, :string, default: nil
  attr :rest, :global

  def link_this_modal(assigns) do
    ~H"""
    <div :if={@show} id="link-this-modal">
      <%!-- Backdrop: standalone layer; clicking it closes. The dialog is a
           SIBLING (next layer), never a child, so inner clicks never bubble
           into this close handler (BUG-060; mirrors the command palette). --%>
      <div
        id="link-this-modal-backdrop"
        class="fixed inset-0 z-40 bg-black/50"
        phx-click="close_link_modal"
      >
      </div>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-none">
        <dialog
          open
          class="relative bg-white dark:bg-gray-800 rounded-lg shadow-xl p-6 w-full max-w-md pointer-events-auto"
          {@rest}
        >
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
            🔗 Link this block
          </h2>
          <button
            type="button"
            phx-click="close_link_modal"
            class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <form id="link-form" phx-submit="submit_link">
          <div class="space-y-4">
            <div
              :if={@error}
              class="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-sm text-red-800 dark:text-red-200"
            >
              {@error}
            </div>

            <div>
              <label
                for="link-kind"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
              >
                Relationship type
              </label>
              <select
                id="link-kind"
                name="kind"
                required
                class="block w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
              >
                <option value="relates_to">Relates to</option>
                <option value="cites">Cites</option>
                <option value="contradicts">Contradicts</option>
                <option value="see_also">See also</option>
              </select>
            </div>

            <div>
              <label
                for="link-note"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
              >
                Note (optional)
              </label>
              <textarea
                id="link-note"
                name="note"
                rows="3"
                placeholder="Add context about this relationship..."
                class="block w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500"
              >
              </textarea>
            </div>

            <input type="hidden" name="source_block_id" value={@source_block_id} />
            <input type="hidden" name="target_block_id" value={@target_block_id} />

            <div class="flex justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_link_modal"
                class="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={@source_block_id == @target_block_id}
              >
                Create Link
              </button>
            </div>
          </div>
        </form>
        </dialog>
      </div>
    </div>
    """
  end
end
