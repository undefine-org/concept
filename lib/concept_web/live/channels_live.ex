defmodule ConceptWeb.ChannelsLive do
  @moduledoc """
  Channels — the full-screen projection of the conversation substrate.

  This is the global home for team communications: the adaptive rail
  (host › conversation, grouped by `Concept.Chat.RailModel`) plus the active
  thread, rendered at full width rather than as the slide-in panel that
  `WorkspaceLive` mounts. Same `ConceptWeb.ChatComponent`, different projection
  — Channels is to chat what the Inbox LiveView is to the inbox feed.

  The peek drawer on a page (`WorkspaceLive`, bottom-right "Chat") deep-links
  here via `/w/:slug/channels/:conversation_id`, handing a specific conversation
  off to the full-screen view.

  Read-only over domain code-interface fns — no `Ash.Query` in the web layer
  (Credo EX9001). Chat reads/writes happen inside the ChatComponent.
  """
  use ConceptWeb, :live_view

  alias Concept.Pages

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Concept.Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} when not is_nil(ws) ->
        if connected?(socket) do
          # Same subscription WorkspaceLive establishes: new-conversation
          # broadcasts addressed to this user. Per-conversation message and
          # presence topics are subscribed inside the ChatComponent.
          ConceptWeb.ChatComponent.subscribe(user, socket)
        end

        pages =
          case Pages.list_tree(actor: user, tenant: ws.id) do
            {:ok, list} -> list
            _ -> []
          end

        {:ok,
         socket
         |> assign(
           workspace: ws,
           pages: pages,
           page_title: "Channels",
           conversation_id: nil,
           unread_count: Concept.Knowledge.Chat.unread_count(actor: user, tenant: ws.id)
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :conversation_id, params["conversation_id"])}
  end

  # The ChatComponent asks its parent to navigate when a conversation is
  # selected/created. In the full-screen projection that is a URL change so the
  # active thread is shareable and back/forward works. nil → the rail home.
  @impl true
  def handle_info({:chat_component_navigate, conversation_id}, socket) do
    slug = socket.assigns.workspace.slug

    path =
      if conversation_id,
        do: ~p"/w/#{slug}/channels/#{conversation_id}",
        else: ~p"/w/#{slug}/channels"

    {:noreply, push_patch(socket, to: path)}
  end

  # Chat → page: a conversation was crystallized onto a page. Refresh the tree so
  # the rail's page-host labels stay accurate.
  def handle_info({:conversation_crystallized, _page_id}, socket) do
    user = socket.assigns.current_user
    ws = socket.assigns.workspace

    socket =
      case Pages.list_tree(actor: user, tenant: ws.id) do
        {:ok, pages} -> assign(socket, :pages, pages)
        _ -> socket
      end

    {:noreply, put_flash(socket, :info, "Conversation crystallized into the page.")}
  end

  # Per-conversation presence (T3) belongs to the ChatComponent — forward it.
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: "chat:conversation:" <> _} =
          broadcast,
        socket
      ) do
    send_update(ConceptWeb.ChatComponent, id: chat_id(socket), broadcast: broadcast)
    {:noreply, socket}
  end

  # Chat message/conversation broadcasts are subscribed by the ChatComponent
  # (which lives in this process). Forward so it can stream new messages /
  # refresh the rail; without this a chat broadcast would crash the LiveView.
  def handle_info(%Phoenix.Socket.Broadcast{topic: "chat:" <> _} = broadcast, socket) do
    send_update(ConceptWeb.ChatComponent, id: chat_id(socket), broadcast: broadcast)
    {:noreply, refresh_unread(socket)}
  end

  # The chat component advanced a read cursor — refresh the sidebar badge.
  def handle_info(:chat_unread_changed, socket), do: {:noreply, refresh_unread(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Sidebar shell events that target the workspace surface: route there.
  @impl true
  def handle_event(event, _params, socket)
      when event in ~w(open_command_palette toggle_chat new_page toggle_live_rail) do
    {:noreply, push_navigate(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  defp chat_id(socket), do: "channels-chat-#{socket.assigns.workspace.id}"

  defp refresh_unread(socket) do
    assign(
      socket,
      :unread_count,
      Concept.Knowledge.Chat.unread_count(
        actor: socket.assigns.current_user,
        tenant: socket.assigns.workspace.id
      )
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace
      id="channels-shell"
      flash={@flash}
      current_scope={@current_scope}
      workspace={@workspace}
      pages={@pages}
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <div class="h-full max-h-full overflow-hidden">
        <.live_component
          module={ConceptWeb.ChatComponent}
          id={"channels-chat-#{@workspace.id}"}
          current_user={@current_user}
          workspace_id={@workspace.id}
          hide_sidebar={false}
          resume_host?={false}
          message_scope={:workspace}
          message_profile={:default}
          conversation_id={@conversation_id}
          host_type={:workspace}
          host_id={nil}
        />
      </div>
    </Layouts.workspace>
    """
  end
end
