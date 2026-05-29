defmodule ConceptWeb.CommandPaletteLive do
  @moduledoc "Cmd-K command palette overlay for searching pages and running commands."
  use ConceptWeb, :live_component

  alias Concept.Pages
  alias Concept.Knowledge.Search

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
  def mount(socket) do
    # Always initialize so handlers stay safe when the palette is closed.
    # `phx-window-keydown` is only rendered while open (see render/1), but
    # these defaults keep palette_key/dispatch_selected total against any
    # stale event delivered before/after a re-render.
    socket =
      socket
      |> assign(:query, "")
      |> assign(:selected_index, 0)
      |> assign(:actions, @actions)
      |> assign_async(:title_results, fn -> {:ok, %{title_results: []}} end)
      |> assign_async(:semantic_results, fn -> {:ok, %{semantic_results: []}} end)

    {:ok, socket}
  end

  @impl true
  def update(%{show_palette: true} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:query, "")
      |> assign(:selected_index, 0)
      |> assign(:actions, @actions)
      |> fetch_title_results("")
      |> assign_async(:semantic_results, fn -> {:ok, %{semantic_results: []}} end)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="command-palette">
      <%= if @show_palette do %>
        <div phx-window-keydown="palette_key" phx-target={@myself}>
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

                <%!-- Shortcuts cheatsheet (empty query) --%>
                <%= if @query == "" do %>
                  <div class="px-4 pt-3 pb-1 text-xs font-medium text-notion-text-light uppercase tracking-wide">
                    Shortcuts
                  </div>
                  <ul class="px-4 py-1 space-y-1 text-sm text-notion-text">
                    <li class="flex items-center gap-2">
                      <kbd class="px-1.5 py-0.5 bg-notion-sidebar-hover rounded font-mono text-xs">
                        ⌘K
                      </kbd>
                      <span>Open this palette</span>
                    </li>
                    <li class="flex items-center gap-2">
                      <kbd class="px-1.5 py-0.5 bg-notion-sidebar-hover rounded font-mono text-xs">
                        ⌘J
                      </kbd>
                      <span>Open chat panel</span>
                    </li>
                    <li class="flex items-center gap-2">
                      <kbd class="px-1.5 py-0.5 bg-notion-sidebar-hover rounded font-mono text-xs">
                        /
                      </kbd>
                      <span>Slash menu in editor</span>
                    </li>
                    <li class="flex items-center gap-2">
                      <kbd class="px-1.5 py-0.5 bg-notion-sidebar-hover rounded font-mono text-xs">
                        Esc
                      </kbd>
                      <span>Close any panel</span>
                    </li>
                  </ul>
                <% end %>

                <%!-- Title results bucket --%>
                <% title_pages = title_pages(@title_results) %>
                <%= if title_pages != [] do %>
                  <div class="px-4 pt-3 pb-1 text-xs font-medium text-notion-text-light uppercase tracking-wide">
                    Pages
                  </div>
                  <div>
                    <.page_item
                      :for={{page, idx} <- Enum.with_index(title_pages)}
                      index={length(@actions) + idx}
                      selected_index={@selected_index}
                      icon_emoji={page.icon_emoji}
                      title={page.title}
                      page_id={page.id}
                      icon="hero-document-text"
                      type={:title}
                      myself={@myself}
                    />
                  </div>
                <% end %>

                <%!-- Semantic results bucket --%>
                <% semantic_hits = semantic_hits(assigns) %>
                <%= if semantic_hits != [] do %>
                  <div class="px-4 pt-3 pb-1 text-xs font-medium text-notion-text-light uppercase tracking-wide">
                    Semantic matches
                  </div>
                  <div>
                    <.semantic_item
                      :for={{hit, idx} <- Enum.with_index(semantic_hits)}
                      index={length(@actions) + title_count(@title_results) + idx}
                      selected_index={@selected_index}
                      hit={hit}
                      myself={@myself}
                    />
                  </div>
                <% end %>

                <%!-- Ask answer row --%>
                <%= if @query != "" do %>
                  <.ask_answer_item
                    index={length(@actions) + title_count(@title_results) + semantic_count(assigns)}
                    selected_index={@selected_index}
                    query={@query}
                    myself={@myself}
                  />
                <% end %>
              </div>
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
      data-type={@type}
      data-page-id={@page_id}
      class={[
        "w-full text-left px-4 py-2 flex items-center gap-3 text-sm",
        @index == @selected_index && "bg-notion-hover"
      ]}
      phx-click="select_item"
      phx-value-index={@index}
      phx-target={@myself}
      phx-mouseenter="hover_item"
    >
      <%= if @icon do %>
        <.icon name={@icon} class="size-4 text-notion-text-light" />
      <% else %>
        <span class="text-base">{@icon_emoji || "📄"}</span>
      <% end %>
      <span class="truncate text-notion-text">{@title || "Untitled"}</span>
    </button>
    """
  end

  defp semantic_item(assigns) do
    # TODO: When CitationCard is available, use it via Code.ensure_loaded? check
    # For now, use inline fallback to avoid compile-time dependency
    ~H"""
    <button
      type="button"
      id={"palette-item-#{@index}"}
      data-type="semantic"
      data-page-id={@hit.page_id}
      data-block-id={@hit.block_id}
      class={[
        "w-full text-left px-4 py-2 flex items-center gap-3 text-sm",
        @index == @selected_index && "bg-notion-hover"
      ]}
      phx-click="select_item"
      phx-value-index={@index}
      phx-target={@myself}
      phx-mouseenter="hover_item"
    >
      <.icon name="hero-sparkles" class="size-4 text-notion-text-light" />
      <div class="flex-1 min-w-0">
        <div class="text-notion-text truncate">
          {@hit.breadcrumbs || "Untitled"}
        </div>
        <div class="text-xs text-notion-text-light truncate">
          {@hit.snippet}
        </div>
      </div>
    </button>
    """
  end

  defp ask_answer_item(assigns) do
    ~H"""
    <button
      type="button"
      id={"palette-item-#{@index}"}
      data-type="ask_answer"
      class={[
        "w-full text-left px-4 py-2 flex items-center gap-3 text-sm",
        @index == @selected_index && "bg-notion-hover"
      ]}
      phx-click="select_item"
      phx-value-index={@index}
      phx-target={@myself}
      phx-mouseenter="hover_item"
    >
      <.icon name="hero-chat-bubble-left-right" class="size-4 text-notion-text-light" />
      <span class="truncate text-notion-text">Ask answer for "{@query}"</span>
    </button>
    """
  end

  @impl true
  def handle_event("palette_search", %{"value" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:selected_index, 0)
      |> fetch_title_results(query)
      |> fetch_semantic_results(query)

    {:noreply, socket}
  end

  @impl true
  def handle_event("palette_key", %{"key" => key}, socket) do
    if not Map.get(socket.assigns, :show_palette, false) do
      # Defense in depth: phx-window-keydown is rendered conditionally, but a
      # stale event in flight during close should never crash the LV.
      {:noreply, socket}
    else
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

  # Accessors — single source of truth for the async result shapes. The
  # assign_async/3 fn returns {:ok, %{title_results: pages}}; LiveView unwraps
  # the *value* of that key, so AsyncResult.result is the bare list (not the
  # wrapping map). render/1, the *_count/1 helpers, and dispatch_selected/1 all
  # read through these so they can never diverge again (BUG-058).
  defp title_pages(%Phoenix.LiveView.AsyncResult{ok?: true, result: pages}) when is_list(pages),
    do: Enum.take(pages, 4)

  defp title_pages(_), do: []

  defp semantic_hits(assigns) do
    case assigns.semantic_results do
      %Phoenix.LiveView.AsyncResult{ok?: true, result: hits} when is_list(hits) ->
        title_page_ids = title_pages(assigns.title_results) |> Enum.map(& &1.id)

        hits
        |> Enum.uniq_by(& &1.page_id)
        |> Enum.reject(&(&1.page_id in title_page_ids))
        |> Enum.take(6)

      _ ->
        []
    end
  end

  defp title_count(async), do: length(title_pages(async))

  defp semantic_count(assigns), do: length(semantic_hits(assigns))

  defp ask_count(assigns) do
    if assigns.query != "", do: 1, else: 0
  end

  defp total_count(assigns) do
    length(@actions) + title_count(assigns.title_results) + semantic_count(assigns) +
      ask_count(assigns)
  end

  defp fetch_title_results(socket, "") do
    user = socket.assigns.current_user
    ws = socket.assigns.workspace

    assign_async(socket, :title_results, fn ->
      case Pages.recent_pages(actor: user, tenant: ws.id) do
        {:ok, pages} -> {:ok, %{title_results: pages}}
        _ -> {:ok, %{title_results: []}}
      end
    end)
  end

  defp fetch_title_results(socket, query) do
    user = socket.assigns.current_user
    ws = socket.assigns.workspace

    assign_async(socket, :title_results, fn ->
      case Pages.search_titles(query, actor: user, tenant: ws.id) do
        {:ok, pages} -> {:ok, %{title_results: pages}}
        _ -> {:ok, %{title_results: []}}
      end
    end)
  end

  defp fetch_semantic_results(socket, "") do
    assign_async(socket, :semantic_results, fn ->
      {:ok, %{semantic_results: []}}
    end)
  end

  defp fetch_semantic_results(socket, query) do
    ws = socket.assigns.workspace

    assign_async(socket, :semantic_results, fn ->
      case Search.search(query, ws.id, limit: 6, mode: :hybrid) do
        {:ok, hits} -> {:ok, %{semantic_results: hits}}
        {:error, _reason} -> {:ok, %{semantic_results: []}}
      end
    end)
  end

  defp dispatch_selected(socket) do
    index = socket.assigns.selected_index
    action_count = length(@actions)
    title_pages = title_pages(socket.assigns.title_results)
    semantic_hits = semantic_hits(socket.assigns)
    title_ct = length(title_pages)
    semantic_ct = length(semantic_hits)

    cond do
      # Action selected
      index < action_count ->
        action = Enum.at(@actions, index)
        send(self(), action.event)
        push_event(socket, "palette_state", %{open: false})

      # Title result selected
      index < action_count + title_ct ->
        page = Enum.at(title_pages, index - action_count)

        if page do
          send(self(), {:palette_navigate, page.id})
        end

        socket

      # Semantic result selected
      index < action_count + title_ct + semantic_ct ->
        hit = Enum.at(semantic_hits, index - action_count - title_ct)

        if hit do
          send(self(), {:palette_navigate, hit.page_id, hit.block_id})
        end

        socket

      # Ask answer selected
      true ->
        query = socket.assigns.query
        ws_id = socket.assigns.workspace.id
        Phoenix.PubSub.broadcast(Concept.PubSub, "palette:#{ws_id}", {:palette_ask, query})
        send(self(), :close_command_palette)
        socket
    end
  end
end
