defmodule ConceptWeb.Components.Sidebar do
  @moduledoc "Sidebar function component for the workspace shell."
  use ConceptWeb, :html

  attr :workspace, :map, required: true
  attr :pages, :list, default: []
  attr :current_page, :map, default: nil
  attr :current_user, :map, required: true
  attr :live_rail_show, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <aside class="ora-sidebar flex flex-col h-screen shrink-0">
      <div class="flex items-center gap-2 px-3 py-2 font-medium text-notion-text">
        <span class="text-lg">{@workspace.icon_emoji || "🏠"}</span>
        <span class="truncate">{@workspace.name}</span>
      </div>

      <button
        type="button"
        phx-click="open_command_palette"
        class="ora-sidebar-row mx-2 mb-1 text-notion-text-light"
      >
        <.icon name="hero-magnifying-glass-micro" class="size-4" />
        <span>Search... (⌘K)</span>
      </button>

      <button
        type="button"
        phx-click="new_page"
        class="ora-sidebar-row mx-2 mb-2 text-notion-text font-medium"
      >
        <.icon name="hero-plus-micro" class="size-4" />
        <span>+ New page</span>
      </button>

      <div class="flex-1 overflow-y-auto px-2">
        <.live_component
          module={ConceptWeb.Components.PageTree}
          id="page-tree"
          pages={@pages}
          workspace={@workspace}
          current_page_id={@current_page && @current_page.id}
        />
      </div>

      <div class="mt-auto border-t border-notion-divider pt-2 px-2 pb-2">
        <button
          type="button"
          phx-click="toggle_live_rail"
          class="ora-sidebar-row text-xs text-notion-text-light mb-2"
        >
          <.icon name="hero-link-micro" class="size-4" />
          <span>Related blocks</span>
          <span class="ml-auto">{if @live_rail_show, do: "✓", else: ""}</span>
        </button>
        <div class="ora-sidebar-row text-xs text-notion-text-light">
          <span class="truncate">{@current_user.email}</span>
          <.link href={~p"/sign-out"} method="delete" class="ml-auto hover:text-notion-text">
            Sign out
          </.link>
        </div>
      </div>
    </aside>
    """
  end
end
