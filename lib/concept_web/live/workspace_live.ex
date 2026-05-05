defmodule ConceptWeb.WorkspaceLive do
  @moduledoc "Workspace shell — full Notion-style application shell."
  use ConceptWeb, :live_view

  import ConceptWeb.Components.Sidebar
  import ConceptWeb.Components.PresenceBar

  alias Concept.Accounts
  alias Concept.Pages

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.live_action == :index do
      user = socket.assigns.current_user

      case Accounts.Workspace.for_user(user.id, actor: user) do
        {:ok, [ws | _]} ->
          {:ok, push_navigate(socket, to: ~p"/w/#{ws.slug}")}

        _ ->
          {:ok,
           socket
           |> put_flash(:error, "No workspace found")
           |> push_navigate(to: ~p"/")}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :workspace -> handle_workspace_params(params, socket)
      :page -> handle_page_params(params, socket)
      _ -> {:noreply, socket}
    end
  end

  defp handle_workspace_params(%{"workspace_slug" => slug}, socket) do
    user = socket.assigns.current_user

    case load_workspace(slug, user) do
      {:ok, ws} ->
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:pages")
        {:ok, pages} = Pages.list_tree(actor: user, tenant: ws.id)

        {:noreply,
         assign(socket,
           workspace: ws,
           pages: pages,
           current_page: nil,
           page_title: ws.name,
           show_palette: false
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp handle_page_params(%{"workspace_slug" => slug, "page_id" => page_id}, socket) do
    user = socket.assigns.current_user

    case load_workspace(slug, user) do
      {:ok, ws} ->
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:pages")
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:page:#{page_id}:presence")
        {:ok, pages} = Pages.list_tree(actor: user, tenant: ws.id)

        case Pages.get_page(page_id, actor: user, tenant: ws.id) do
          {:ok, page} ->
            {:noreply,
             assign(socket,
               workspace: ws,
               pages: pages,
               current_page: page,
               page_title: page.title,
               show_palette: false
             )}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, "Page not found")
             |> push_navigate(to: ~p"/w/#{slug}")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp load_workspace(slug, user) do
    case Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} when not is_nil(ws) -> {:ok, ws}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def handle_info({:ash_pubsub, event, _payload}, socket)
      when event in ["page_created", "page_updated", "page_archived", "page_restored"] do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    case Pages.list_tree(actor: user, tenant: ws.id) do
      {:ok, pages} -> {:noreply, assign(socket, :pages, pages)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to refresh pages")}
    end
  end

  def handle_info({:new_child_page, parent_id}, socket) do
    handle_event("new_child_page", %{"parent_id" => parent_id}, socket)
  end

  def handle_info({:archive_page, id}, socket) do
    handle_event("archive_page", %{"id" => id}, socket)
  end

  def handle_info(:close_command_palette, socket) do
    close_palette(socket)
  end

  def handle_info(:palette_new_page, socket) do
    {:noreply, do_new_page(socket, nil)}
  end

  def handle_info(:palette_sign_out, socket) do
    {:noreply, redirect(socket, to: ~p"/sign-out")}
  end

  def handle_info({:palette_navigate, page_id}, socket) do
    slug = socket.assigns.workspace.slug
    {:noreply, push_navigate(socket, to: ~p"/w/#{slug}/p/#{page_id}")}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: _payload},
        socket
      ) do
    if socket.assigns[:current_page] do
      presence_list =
        ConceptWeb.Presence.list(
          "workspace:#{socket.assigns.workspace.id}:page:#{socket.assigns.current_page.id}:presence"
        )

      users =
        Enum.map(presence_list, fn {user_id, %{metas: metas}} ->
          meta = List.first(metas)

          %{
            id: user_id,
            display_name: meta.display_name,
            color: meta.color,
            online_at: meta.online_at
          }
        end)
        |> Enum.uniq_by(& &1.id)

      {:noreply, assign(socket, :presence_users, users)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("new_page", _, socket) do
    {:noreply, do_new_page(socket, nil)}
  end

  def handle_event("new_child_page", %{"parent_id" => parent_id}, socket) do
    {:noreply, do_new_page(socket, parent_id)}
  end

  def handle_event("rename_page", %{"id" => id, "title" => title}, socket) do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    case Pages.get_page(id, actor: user, tenant: ws.id) do
      {:ok, page} ->
        case Pages.rename_page(page, title, actor: user, tenant: ws.id) do
          {:ok, _} -> {:noreply, socket}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to rename page")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Page not found")}
    end
  end

  def handle_event("archive_page", %{"id" => id}, socket) do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    case Pages.get_page(id, actor: user, tenant: ws.id) do
      {:ok, page} ->
        case Pages.archive(page, actor: user, tenant: ws.id) do
          {:ok, _} ->
            if socket.assigns[:current_page] && socket.assigns.current_page.id == id do
              {:noreply, push_patch(socket, to: ~p"/w/#{ws.slug}")}
            else
              {:noreply, socket}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to archive page")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Page not found")}
    end
  end

  @impl true
  def handle_event("global_key", %{"key" => "k", "metaKey" => true}, socket) do
    toggle_palette(socket)
  end

  def handle_event("global_key", %{"key" => "k", "ctrlKey" => true}, socket) do
    toggle_palette(socket)
  end

  def handle_event("global_key", %{"key" => "Escape"}, socket) do
    if socket.assigns[:show_palette] do
      close_palette(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("global_key", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_command_palette", _params, socket) do
    open_palette(socket)
  end

  @impl true
  def handle_event("close_command_palette", _params, socket) do
    close_palette(socket)
  end

  defp do_new_page(socket, parent_id) do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    case Pages.create_page("", ws.id, parent_id, actor: user, tenant: ws.id) do
      {:ok, page} ->
        push_patch(socket, to: ~p"/w/#{ws.slug}/p/#{page.id}")

      {:error, _} ->
        put_flash(socket, :error, "Failed to create page")
    end
  end

  defp toggle_palette(socket) do
    if socket.assigns[:show_palette] do
      close_palette(socket)
    else
      open_palette(socket)
    end
  end

  defp open_palette(socket) do
    {:noreply,
     socket
     |> assign(show_palette: true)
     |> push_event("palette_state", %{open: true})}
  end

  defp close_palette(socket) do
    {:noreply,
     socket
     |> assign(show_palette: false)
     |> push_event("palette_state", %{open: false})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="workspace-root"
      class="flex h-screen"
      phx-hook="GlobalKeys"
      phx-window-keydown="global_key"
    >
      <.sidebar
        workspace={@workspace}
        pages={@pages}
        current_page={@current_page}
        current_user={@current_user}
      />

      <main class="flex-1 overflow-y-auto bg-notion-bg">
        <%= if @current_page == nil do %>
          <div class="flex flex-col items-center justify-center h-full text-notion-text-light">
            <p class="mb-4 text-lg">Pick a page or create one</p>
            <button
              type="button"
              phx-click="new_page"
              class="px-4 py-2 bg-notion-blue text-white rounded hover:opacity-90"
            >
              + New page
            </button>
          </div>
        <% else %>
          <div class="ora-page-canvas">
            <.presence_bar users={@presence_users} />
            <h1 class="text-4xl font-bold mb-4">
              {@current_page.icon_emoji || "📄"}
              {if @current_page.title == "" || is_nil(@current_page.title),
                do: "Untitled",
                else: @current_page.title}
            </h1>
            {live_render(@socket, ConceptWeb.PageEditorLive,
              id: "page-editor-#{@current_page.id}",
              session: %{
                "workspace_id" => @workspace.id,
                "page_id" => @current_page.id,
                "user_id" => @current_user.id
              }
            )}
          </div>
        <% end %>
      </main>
    </div>

    <.live_component
      module={ConceptWeb.CommandPaletteLive}
      id="command-palette"
      workspace={@workspace}
      current_user={@current_user}
      show_palette={@show_palette}
    />
    """
  end
end
