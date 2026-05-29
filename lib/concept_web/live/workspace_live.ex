defmodule ConceptWeb.WorkspaceLive do
  @moduledoc "Workspace shell — full Notion-style application shell."
  use ConceptWeb, :live_view

  import ConceptWeb.Components.Sidebar
  import ConceptWeb.Components.PresenceBar
  import ConceptWeb.Components.IndexingPill
  import ConceptWeb.Components.LinkThisModal
  import ConceptWeb.Components.LiveCitationRail

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
        ConceptWeb.Endpoint.subscribe("workspace:#{ws.id}:pages")
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:ingest")
        Phoenix.PubSub.subscribe(Concept.PubSub, "palette:#{ws.id}")
        {:ok, pages} = Pages.list_tree(actor: user, tenant: ws.id)

        {:noreply,
         assign(socket,
           workspace: ws,
           pages: pages,
           current_page: nil,
           page_title: ws.name,
           show_palette: false,
           presence_users: [],
           indexing_state: %{count: 0, last_succeeded_at: nil, failed?: false},
           show_indexing_details: false,
           chat_open?: false,
           chat_initial_prompt: nil,
           link_modal_state: nil,
           live_rail_results: [],
           live_rail_show: false,
           live_rail_debounce_ref: nil
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
        ConceptWeb.Endpoint.subscribe("workspace:#{ws.id}:pages")
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:ingest")
        Phoenix.PubSub.subscribe(Concept.PubSub, "palette:#{ws.id}")
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:page:#{page_id}:presence")
        Phoenix.PubSub.subscribe(Concept.PubSub, "workspace:#{ws.id}:focus_block")
        {:ok, pages} = Pages.list_tree(actor: user, tenant: ws.id)

        case Pages.get_page(page_id, actor: user, tenant: ws.id) do
          {:ok, page} ->
            {:noreply,
             assign(socket,
               workspace: ws,
               pages: pages,
               current_page: page,
               page_title: page.title,
               show_palette: false,
               presence_users: [],
               indexing_state: %{count: 0, last_succeeded_at: nil, failed?: false},
               show_indexing_details: false,
               chat_open?: false,
               chat_initial_prompt: nil,
               link_modal_state: nil,
               live_rail_results: [],
               live_rail_show: false,
               live_rail_debounce_ref: nil
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

  def handle_info({:palette_navigate, page_id, block_id}, socket) do
    slug = socket.assigns.workspace.slug
    path = ~p"/w/#{slug}/p/#{page_id}" <> "#block-#{block_id}"
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:palette_navigate, page_id}, socket) do
    slug = socket.assigns.workspace.slug
    {:noreply, push_navigate(socket, to: ~p"/w/#{slug}/p/#{page_id}")}
  end

  def handle_info({:palette_ask, query}, socket) do
    {:noreply, socket |> put_chat_open(true) |> assign(chat_initial_prompt: query)}
  end

  def handle_info({:palette_ask_with_seed, text, page_id}, socket) do
    prompt = "Tell me more about this excerpt:\n\n" <> text

    socket = socket |> put_chat_open(true) |> assign(chat_initial_prompt: prompt)

    send_update(ConceptWeb.WorkspaceLive.ChatPanel,
      id: "chat-panel",
      message_scope: :subtree,
      scope_target_id: page_id
    )

    {:noreply, socket}
  end

  def handle_info(:close_chat_panel, socket) do
    {:noreply, put_chat_open(socket, false)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: event, payload: notification},
        socket
      )
      when event in ["page_created", "page_updated", "page_archived", "page_restored"] do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    socket =
      case Pages.list_tree(actor: user, tenant: ws.id) do
        {:ok, pages} -> assign(socket, :pages, pages)
        _ -> socket
      end

    socket =
      case {event, notification, socket.assigns[:current_page]} do
        {"page_updated", %{data: %{id: id} = page}, %{id: id}} ->
          send_update(ConceptWeb.Components.PageHeader,
            id: "page-header-#{page.id}",
            page: page,
            current_user: socket.assigns.current_user
          )

          socket
          |> assign(:current_page, page)
          |> assign(:page_title, page.title)

        {"page_archived", %{data: %{id: id}}, %{id: id}} ->
          socket
          |> assign(:current_page, nil)
          |> assign(:page_title, ws.name)
          |> push_patch(to: ~p"/w/#{ws.slug}")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "ingest_started", payload: _notification},
        socket
      ) do
    state = socket.assigns.indexing_state
    new_state = %{state | count: state.count + 1, failed?: false}
    {:noreply, assign(socket, :indexing_state, new_state)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "ingest_succeeded", payload: _notification},
        socket
      ) do
    state = socket.assigns.indexing_state

    new_state = %{
      state
      | count: max(0, state.count - 1),
        last_succeeded_at: DateTime.utc_now(),
        failed?: false
    }

    {:noreply, assign(socket, :indexing_state, new_state)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "ingest_failed", payload: _notification},
        socket
      ) do
    state = socket.assigns.indexing_state
    new_state = %{state | count: max(0, state.count - 1), failed?: true}
    {:noreply, assign(socket, :indexing_state, new_state)}
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
  def handle_info({:focus_block, _block_id, text, page_id}, socket) do
    # Cancel previous debounce if exists
    if socket.assigns.live_rail_debounce_ref do
      Process.cancel_timer(socket.assigns.live_rail_debounce_ref)
    end

    # Schedule new search after 1.5s
    ref = Process.send_after(self(), {:execute_rail_search, text, page_id}, 1500)
    {:noreply, assign(socket, live_rail_debounce_ref: ref)}
  end

  def handle_info({:execute_rail_search, text, page_id}, socket) do
    ws_id = socket.assigns.workspace.id

    case Concept.Knowledge.Search.search(text, ws_id, limit: 3, mode: :hybrid) do
      {:ok, results} ->
        # Filter out results from current page
        filtered =
          results
          |> Enum.filter(fn hit -> hit.page_id != page_id end)
          |> Enum.take(3)

        {:noreply, assign(socket, live_rail_results: filtered, live_rail_debounce_ref: nil)}

      {:error, _} ->
        {:noreply, assign(socket, live_rail_debounce_ref: nil)}
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

  def handle_event("show_indexing_details", _params, socket) do
    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    jobs = Concept.Knowledge.recent_ingestion_jobs!(actor: user, tenant: ws.id)

    {:noreply, assign(socket, show_indexing_details: true, indexing_jobs: jobs)}
  end

  def handle_event("hide_indexing_details", _params, socket) do
    {:noreply, assign(socket, show_indexing_details: false)}
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, put_chat_open(socket, !socket.assigns.chat_open?)}
  end

  # Escape priority: dismiss the palette first, then the chat panel. Owned by
  # the GlobalKeys hook (the sole keyboard authority); see FUP-034.
  def handle_event("escape", _params, socket) do
    cond do
      socket.assigns[:show_palette] -> close_palette(socket)
      socket.assigns[:chat_open?] -> {:noreply, put_chat_open(socket, false)}
      true -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_command_palette", _params, socket) do
    open_palette(socket)
  end

  @impl true
  def handle_event("close_command_palette", _params, socket) do
    close_palette(socket)
  end

  @impl true
  def handle_event("ora_link_this", %{"targetBlockId" => target_block_id}, socket) do
    # Determine source block from current page's focused block or first block
    # For now, we'll require the event to include source_block_id or use current page's first block
    source_block_id = determine_source_block(socket)

    {:noreply,
     assign(socket, :link_modal_state, %{
       target_block_id: target_block_id,
       source_block_id: source_block_id,
       error: nil
     })}
  end

  def handle_event("close_link_modal", _params, socket) do
    {:noreply, assign(socket, :link_modal_state, nil)}
  end

  def handle_event("toggle_live_rail", _params, socket) do
    new_state = !socket.assigns.live_rail_show

    socket =
      socket
      |> assign(live_rail_show: new_state)
      |> push_event("rail_toggled", %{show: new_state})

    {:noreply, socket}
  end

  def handle_event("set_live_rail_show", %{"show" => show}, socket) do
    {:noreply, assign(socket, live_rail_show: show)}
  end

  def handle_event("submit_link", params, socket) do
    %{
      "kind" => kind,
      "source_block_id" => source_block_id,
      "target_block_id" => target_block_id
    } = params

    note = Map.get(params, "note", "")

    ws = socket.assigns.workspace
    user = socket.assigns.current_user

    # Validate self-link at backend too
    if source_block_id == target_block_id do
      {:noreply,
       assign(socket, :link_modal_state, %{
         target_block_id: target_block_id,
         source_block_id: source_block_id,
         error: "Cannot link a block to itself"
       })}
    else
      link_attrs = %{
        source_block_id: source_block_id,
        target_block_id: target_block_id,
        kind: String.to_existing_atom(kind),
        note: if(note == "", do: nil, else: note),
        workspace_id: ws.id
      }

      case Concept.Knowledge.create_link(link_attrs, actor: user, tenant: ws.id) do
        {:ok, _link} ->
          {:noreply,
           socket
           |> assign(:link_modal_state, nil)
           |> put_flash(:info, "✓ Linked")}

        {:error, %Ash.Error.Invalid{errors: errors}} ->
          error_msg =
            errors
            |> Enum.map(fn
              %{message: msg} -> msg
              _ -> "Failed to create link"
            end)
            |> Enum.join(", ")

          {:noreply,
           assign(socket, :link_modal_state, %{
             target_block_id: target_block_id,
             source_block_id: source_block_id,
             error: error_msg
           })}

        {:error, _} ->
          {:noreply,
           assign(socket, :link_modal_state, %{
             target_block_id: target_block_id,
             source_block_id: source_block_id,
             error: "Failed to create link"
           })}
      end
    end
  end

  defp determine_source_block(socket) do
    # For now, return the current page's first block if available
    # Future: track focused block in assigns
    case socket.assigns[:current_page] do
      %{id: page_id} ->
        ws = socket.assigns.workspace
        user = socket.assigns.current_user

        case Concept.Pages.first_block_for_page(page_id, actor: user, tenant: ws.id) do
          {:ok, %{id: id}} -> id
          _ -> nil
        end

      _ ->
        nil
    end
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

  # Single source of truth for chat visibility: assign + mirror to the
  # GlobalKeys hook (which gates Escape on the open state). See FUP-034.
  defp put_chat_open(socket, open?) do
    socket
    |> assign(:chat_open?, open?)
    |> push_event("chat_state", %{open: open?})
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
    <Layouts.shell flash={@flash} current_scope={@current_scope}>
      <div
        id="workspace-root"
        class="flex min-h-screen"
        phx-hook="GlobalKeys LiveCitationRail"
      >
        <.sidebar
          workspace={@workspace}
          pages={@pages}
          current_page={@current_page}
          current_user={@current_user}
          live_rail_show={@live_rail_show}
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
              <.live_component
                module={ConceptWeb.Components.PageHeader}
                id={"page-header-#{@current_page.id}"}
                page={@current_page}
                current_user={@current_user}
              />
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

        <.live_citation_rail
          :if={@live_rail_show && @current_page}
          citations={@live_rail_results}
          workspace_slug={@workspace.slug}
          current_page_id={@current_page && @current_page.id}
        />
      </div>

      <div class="fixed bottom-4 right-4 z-30">
        <.indexing_pill
          state={
            if @indexing_state.failed?,
              do: :error,
              else: if(@indexing_state.count > 0, do: :indexing, else: :idle)
          }
          count={@indexing_state.count}
          last_succeeded_at={@indexing_state.last_succeeded_at}
          show_details={@show_indexing_details}
          jobs={Map.get(assigns, :indexing_jobs, [])}
          workspace={@workspace}
          current_user={@current_user}
        />
      </div>

      <.live_component
        :if={@chat_open?}
        module={ConceptWeb.WorkspaceLive.ChatPanel}
        id="chat-panel"
        workspace={@workspace}
        current_user={@current_user}
        open={@chat_open?}
        initial_prompt={@chat_initial_prompt}
      />

      <.live_component
        module={ConceptWeb.CommandPaletteLive}
        id="command-palette"
        workspace={@workspace}
        current_user={@current_user}
        show_palette={@show_palette}
      />

      <.link_this_modal
        :if={@link_modal_state}
        show={@link_modal_state != nil}
        source_block_id={@link_modal_state && @link_modal_state.source_block_id}
        target_block_id={@link_modal_state && @link_modal_state.target_block_id}
        error={@link_modal_state && @link_modal_state.error}
      />
    </Layouts.shell>
    """
  end
end
