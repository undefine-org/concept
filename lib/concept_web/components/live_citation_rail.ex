defmodule ConceptWeb.Components.LiveCitationRail do
  @moduledoc """
  Live citation rail — surfaces semantically related blocks as user types.

  Displays top-3 related blocks from elsewhere in the workspace in a sticky
  right rail. Each citation has a "🔗 Link this" button to trigger FEAT-046 modal.
  """
  use Phoenix.Component
  import ConceptWeb.Components.CitationCard

  @doc """
  Renders the live citation rail with related blocks.

  ## Examples

      <.live_citation_rail
        citations={@live_rail_results}
        workspace_slug={@workspace.slug}
        current_page_id={@current_page.id}
      />
  """
  attr :citations, :list, default: []
  attr :workspace_slug, :string, required: true
  attr :current_page_id, :string, default: nil

  def live_citation_rail(assigns) do
    ~H"""
    <aside class="ora-live-citation-rail">
      <div class="sticky top-4 space-y-2">
        <h3 class="text-sm font-semibold text-notion-text-light px-3">Related</h3>

        <%= if @citations == [] do %>
          <div class="px-3 py-8 text-sm text-notion-text-light text-center">
            No related blocks yet.
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for citation <- @citations do %>
              <div class="relative group">
                <.citation_card
                  citation={citation}
                  workspace_slug={@workspace_slug}

                />
                <button
                  type="button"
                  phx-click="open_link_modal"
                  phx-value-target-block-id={citation.block_id}
                  class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity ora-btn ora-btn--blue ora-btn--sm"
                  title="Link this block"
                >
                  🔗 Link this
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </aside>
    """
  end
end
