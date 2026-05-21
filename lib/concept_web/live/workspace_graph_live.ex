defmodule ConceptWeb.WorkspaceGraphLive do
  @moduledoc "Workspace knowledge graph visualization with Leiden community coloring."
  use ConceptWeb, :live_view

  alias Concept.Accounts
  alias Concept.Knowledge
  alias Concept.Pages
  alias ConceptWeb.Components.Sidebar

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} when not is_nil(ws) ->
        ConceptWeb.Endpoint.subscribe("workspace:#{ws.id}:pages")
        {:ok, pages} = Pages.list_tree(actor: user, tenant: ws.id)

        {:ok,
         assign(socket,
           workspace: ws,
           pages: pages,
           graph_data: %{nodes: [], edges: [], communities: []}
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/w")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    ws = socket.assigns.workspace
    graph_data = Knowledge.graph_for_workspace(ws.id)
    {:noreply, assign(socket, :graph_data, graph_data)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: event},
        socket
      )
      when event in ["page_created", "page_updated", "page_archived"] do
    ws = socket.assigns.workspace
    {:noreply, assign(socket, :graph_data, Knowledge.graph_for_workspace(ws.id))}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell flash={@flash} current_scope={@current_scope}>
      <div class="flex min-h-screen">
        <Sidebar.sidebar
          workspace={@workspace}
          pages={@pages}
          current_user={@current_user}
          live_rail_show={false}
        />

        <main class="flex-1 relative bg-notion-bg overflow-hidden">
          <header class="absolute top-0 left-0 right-0 z-10 px-6 py-3 border-b border-notion-divider bg-white/90 backdrop-blur flex items-center justify-between">
            <div>
              <h1 class="text-sm font-semibold text-notion-text">Knowledge graph</h1>
              <p class="text-xs text-notion-text-light">
                {length(@graph_data.nodes)} nodes · {length(@graph_data.edges)} edges
              </p>
            </div>
            <.link
              navigate={~p"/w/#{@workspace.slug}"}
              class="text-xs text-notion-text-light hover:text-notion-text"
            >
              ← Back to workspace
            </.link>
          </header>

          <div id="workspace-graph-root" class="absolute inset-0 pt-14">
            <%= if @graph_data.nodes == [] do %>
              <div class="flex flex-col items-center justify-center h-full text-notion-text-light gap-2 px-6">
                <span class="text-5xl">🕸️</span>
                <h2 class="text-lg font-medium text-notion-text">No knowledge yet</h2>
                <p class="text-sm max-w-md text-center">
                  Write a few pages and links between blocks will appear here as a graph.
                </p>
              </div>
            <% else %>
              <ora-workspace-graph
                id="workspace-graph"
                data={Jason.encode!(@graph_data)}
                data-nodes-count={length(@graph_data.nodes)}
                data-edges-count={length(@graph_data.edges)}
                workspace-slug={@workspace.slug}
                phx-update="ignore"
              >
              </ora-workspace-graph>
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.shell>
    """
  end
end
