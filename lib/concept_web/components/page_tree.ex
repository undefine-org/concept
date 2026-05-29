defmodule ConceptWeb.Components.PageTree do
  @moduledoc "Nested page tree live_component for the sidebar."
  use ConceptWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_init_expanded(assigns.pages)
      |> assign(:children_map, build_children_map(assigns.pages))

    {:ok, socket}
  end

  defp maybe_init_expanded(socket, pages) do
    if Map.has_key?(socket.assigns, :expanded) do
      socket
    else
      roots = Enum.filter(pages, &is_nil(&1.parent_page_id))
      assign(socket, :expanded, MapSet.new(Enum.map(roots, & &1.id)))
    end
  end

  defp build_children_map(pages) do
    Enum.group_by(pages, & &1.parent_page_id)
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("new_child_page", %{"parent_id" => parent_id}, socket) do
    send(self(), {:new_child_page, parent_id})
    {:noreply, socket}
  end

  def handle_event("archive_page", %{"id" => id}, socket) do
    send(self(), {:archive_page, id})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    roots = assigns.children_map[nil] || []
    assigns = assign(assigns, :root_pages, roots)

    ~H"""
    <ul class="space-y-0.5">
      <%= for page <- @root_pages do %>
        <.page_row page={page} depth={0} {assigns} />
      <% end %>
    </ul>
    """
  end

  defp page_row(assigns) do
    children = assigns.children_map[assigns.page.id] || []
    has_children? = length(children) > 0
    expanded? = MapSet.member?(assigns.expanded, assigns.page.id)
    active? = assigns.current_page_id == assigns.page.id

    assigns =
      assigns
      |> assign(:children, children)
      |> assign(:has_children?, has_children?)
      |> assign(:expanded?, expanded?)
      |> assign(:active?, active?)

    ~H"""
    <li>
      <div
        class={["ora-sidebar-row group", @active? && "active"]}
        style={"padding-left: #{8 + @depth * 16}px"}
      >
        <%= if @has_children? do %>
          <button
            type="button"
            phx-click="toggle_expand"
            phx-value-id={@page.id}
            phx-target={@myself}
            class="w-4 h-4 flex items-center justify-center text-notion-text-light hover:text-notion-text shrink-0"
          >
            {if @expanded?, do: "▼", else: "▶"}
          </button>
        <% else %>
          <span class="w-4 h-4 inline-block shrink-0"></span>
        <% end %>

        <.link
          navigate={~p"/w/#{@workspace.slug}/p/#{@page.id}"}
          class="flex-1 truncate flex items-center gap-1.5 min-w-0"
        >
          <span class="shrink-0">{@page.icon_emoji || "📄"}</span>
          <span class="truncate">
            {if @page.title == "" || is_nil(@page.title), do: "Untitled", else: @page.title}
          </span>
        </.link>

        <div class="hidden group-hover:flex items-center gap-1 shrink-0">
          <button
            type="button"
            phx-click="new_child_page"
            phx-value-parent_id={@page.id}
            phx-target={@myself}
            class="w-5 h-5 flex items-center justify-center rounded hover:bg-notion-sidebar-hover text-notion-text-light"
            title="Add sub-page"
          >
            <.icon name="hero-plus-micro" class="size-3" />
          </button>
          <button
            type="button"
            phx-click="archive_page"
            phx-value-id={@page.id}
            phx-target={@myself}
            data-confirm={"Archive \"#{if @page.title in ["", nil], do: "Untitled", else: @page.title}\"?"}
            class="w-5 h-5 flex items-center justify-center rounded hover:bg-notion-sidebar-hover text-notion-text-light"
            title="Archive"
          >
            <.icon name="hero-archive-box-micro" class="size-3" />
          </button>
        </div>
      </div>

      <%= if @expanded? and @has_children? do %>
        <ul class="space-y-0.5">
          <%= for child <- @children do %>
            <.page_row page={child} depth={@depth + 1} {assigns} />
          <% end %>
        </ul>
      <% end %>
    </li>
    """
  end
end
