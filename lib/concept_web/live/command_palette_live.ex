defmodule ConceptWeb.CommandPaletteLive do
  @moduledoc "Cmd-K command palette overlay for searching pages and running commands."
  use ConceptWeb, :live_component

  alias Concept.Pages

  @actions [
    %{id: "new_page", label: "+ New page", icon: "hero-plus-micro", event: :palette_new_page},
    %{
      id: "sign_out",
      label: "Sign out",
      icon: "hero-arrow-right-start-on-rectangle-micro",
      event: :palette_sign_out
    }
  ]

  @impl true
  def update(%{show_palette: true} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:query, "")
      |> assign(:selected_index, 0)
      |> assign(:actions, @actions)
      |> fetch_results("")

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="command-palette" phx-window-keydown="palette_key" phx-target={@myself}>
      <%= if @show_palette do %>
        <div
          class="fixed inset-0 bg-black/40 z-40"
          phx-click="close_command_palette"
          phx-target={@myself}
        >
        </div>
        <div class="fixed inset-0 flex items-start justify-center z-50 pt-[15vh]">
          <div class="w-full max-w-[600px] bg-white rounded-md shadow-xl overflow-hidden">
            <div class="border-b border-gray-100 px-4 py-3">
              <input
                type="text"
                placeholder="Search pages or run a command..."
                class="w-full text-base outline-none text-notion-text placeholder:text-notion-text-light"
                phx-keyup="palette_search"
                phx-debounce="100"
                phx-target={@myself}
                phx-mounted={Phoenix.LiveView.JS.focus()}
                value={@query}
              />
            </div>

            <div class="max-h-[60vh] overflow-y-auto py-2">
              <div>
                <.action_item
                  :for={{action, idx} <- Enum.with_index(@actions)}
                  index={idx}
                  selected_index={@selected_index}
                  icon={action.icon}
                  label={action.label}
                  myself={@myself}
                />
              </div>

              <%= if @results != [] do %>
                <div class="px-4 pt-3 pb-1 text-xs font-medium text-notion-text-light uppercase tracking-wide">
                  Pages
                </div>
                <div>
                  <.page_item
                    :for={{page, idx} <- Enum.with_index(@results)}
                    index={length(@actions) + idx}
                    selected_index={@selected_index}
                    icon_emoji={page.icon_emoji}
                    title={page.title}
                    myself={@myself}
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp action_item(assigns) do
    ~H"""
    <button
      type="button"
      id={"palette-item-#{@index}"}
      class={[
        "w-full text-left px-4 py-2 flex items-center gap-3 text-sm",
        @index == @selected_index && "bg-notion-hover"
      ]}
      phx-click="select_item"
      phx-value-index={@index}
      phx-target={@myself}
      phx-mouseenter="hover_item"
      phx-value-index={@index}
    >
      <.icon name={@icon} class="size-4 text-notion-text-light" />
      <span class="truncate text-notion-text">{@label}</span>
    </button>
    """
  end

  defp page_item(assigns) do
    ~H"""
    <button
      type="button"
      id={"palette-item-#{@index}"}
      class={[
        "w-full text-left px-4 py-2 flex items-center gap-3 text-sm",
        @index == @selected_index && "bg-notion-hover"
      ]}
      phx-click="select_item"
      phx-value-index={@index}
      phx-target={@myself}
      phx-mouseenter="hover_item"
      phx-value-index={@index}
    >
      <span class="text-base">{@icon_emoji || "📄"}</span>
      <span class="truncate text-notion-text">{@title || "Untitled"}</span>
    </button>
    """
  end

  @impl true
  def handle_event("palette_search", %{"value" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:selected_index, 0)
      |> fetch_results(query)

    {:noreply, socket}
  end

  @impl true
  def handle_event("palette_key", %{"key" => key}, socket) do
    case key do
      "ArrowDown" ->
        max_idx = total_count(socket.assigns) - 1
        {:noreply, update(socket, :selected_index, &min(&1 + 1, max(max_idx, 0)))}

      "ArrowUp" ->
        {:noreply, update(socket, :selected_index, &max(&1 - 1, 0))}

      "Enter" ->
        {:noreply, dispatch_selected(socket)}

      "Escape" ->
        send(self(), :close_command_palette)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    socket = assign(socket, :selected_index, index)
    {:noreply, dispatch_selected(socket)}
  end

  @impl true
  def handle_event("hover_item", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("close_command_palette", _params, socket) do
    send(self(), :close_command_palette)
    {:noreply, socket}
  end

  defp total_count(assigns) do
    length(@actions) + length(assigns.results)
  end

  defp fetch_results(socket, "") do
    user = socket.assigns.current_user
    ws = socket.assigns.workspace

    case Pages.recent_pages(actor: user, tenant: ws.id) do
      {:ok, pages} -> assign(socket, :results, pages)
      _ -> assign(socket, :results, [])
    end
  end

  defp fetch_results(socket, query) do
    user = socket.assigns.current_user
    ws = socket.assigns.workspace

    case Pages.search_titles(query, actor: user, tenant: ws.id) do
      {:ok, pages} -> assign(socket, :results, pages)
      _ -> assign(socket, :results, [])
    end
  end

  defp dispatch_selected(socket) do
    index = socket.assigns.selected_index
    action_count = length(@actions)

    cond do
      index < action_count ->
        action = Enum.at(@actions, index)
        send(self(), action.event)
        push_event(socket, "palette_state", %{open: false})

      true ->
        page = Enum.at(socket.assigns.results, index - action_count)

        if page do
          send(self(), {:palette_navigate, page.id})
          socket
        else
          socket
        end
    end
  end
end
