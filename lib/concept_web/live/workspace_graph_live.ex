defmodule ConceptWeb.WorkspaceGraphLive do
  @moduledoc "Workspace knowledge graph visualization with Leiden community coloring."
  use ConceptWeb, :live_view

  alias Concept.Accounts
  alias Concept.Knowledge

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} when not is_nil(ws) ->
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:pages")
        {:ok, assign(socket, workspace: ws, graph_data: %{nodes: [], edges: [], communities: []})}

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
    <div id="workspace-graph-root" class="h-screen w-full">
      <%= if @graph_data.nodes == [] do %>
        <div class="flex flex-col items-center justify-center h-full text-notion-text-light gap-1 px-6">
          <h2 class="text-lg font-medium text-notion-text">No knowledge yet</h2>
          <p class="text-sm max-w-md text-center">
            Write a few pages and links between blocks will appear here as a graph.
          </p>
        </div>
      <% else %>
        <ora-workspace-graph
          data={Jason.encode!(@graph_data)}
          data-nodes-count={length(@graph_data.nodes)}
          data-edges-count={length(@graph_data.edges)}
          workspace-slug={@workspace.slug}
        >
        </ora-workspace-graph>
      <% end %>
    </div>
    """
  end
end
