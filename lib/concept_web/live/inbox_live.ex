defmodule ConceptWeb.InboxLive do
  @moduledoc """
  Inbox — the one genuinely new feed (PLAN-010 §6.5, §A).

  A recipient-keyed projection over the conversations the current user
  participates in, most recently active first. Agent results and human mentions
  land in the SAME list (one feed) because the domain fans every message out to
  each participant's `inbox:<user_id>` PubSub topic (`BroadcastInbox`); this
  LiveView subscribes to that topic once and re-streams on activity.

  Read-only over domain code-interface fns (`Chat.inbox/0`) — no `Ash.Query`
  in the web layer (Credo EX9001).
  """
  use ConceptWeb, :live_view

  alias Concept.Knowledge.Chat
  alias Concept.Pages

  @impl true
  def mount(%{"workspace_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Concept.Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, ws} when not is_nil(ws) ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Concept.PubSub, "inbox:#{user.id}")
        end

        conversations = list_inbox(user, ws)

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
           page_title: "Inbox",
           inbox_count: length(conversations),
           unread_count: Concept.Knowledge.Chat.unread_count(actor: user, tenant: ws.id)
         )
         |> stream(:conversations, conversations)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event(event, _params, socket)
      when event in ~w(open_command_palette toggle_chat new_page) do
    {:noreply, push_navigate(socket, to: ~p"/w/#{socket.assigns.workspace.slug}")}
  end

  def handle_event("escape", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:inbox_activity, _payload}, socket) do
    # Re-fetch and re-stream: the inbox is a projection, so a single activity
    # event refreshes the whole ordered list (recency changes globally).
    conversations = list_inbox(socket.assigns.current_user, socket.assigns.workspace)

    {:noreply,
     socket
     |> assign(:inbox_count, length(conversations))
     |> stream(:conversations, conversations, reset: true)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp list_inbox(user, ws) do
    case Chat.inbox(actor: user, tenant: ws.id) do
      {:ok, conversations} ->
        conversations

      {:error, reason} ->
        # An empty inbox and a failed read look identical to the user; log so a
        # policy/tenant regression is visible rather than silently swallowed.
        require Logger
        Logger.warning("inbox read failed for user=#{user.id}: #{inspect(reason)}")
        []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace
      id="inbox-shell"
      flash={@flash}
      current_scope={@current_scope}
      workspace={@workspace}
      pages={@pages}
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <div class="max-w-3xl mx-auto p-6">
        <div class="mb-6 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-bell" class="size-5 text-notion-text" />
            <h1 class="text-2xl font-bold text-notion-text">Inbox</h1>
            <span class="text-sm text-notion-text-light">
              {@inbox_count} active {ngettext("conversation", "conversations", @inbox_count)}
            </span>
          </div>
          <.link
            navigate={~p"/w/#{@workspace.slug}"}
            class="text-sm text-notion-text-light hover:text-notion-text"
          >
            ← Workspace
          </.link>
        </div>

        <div
          id="inbox-list"
          phx-update="stream"
          class="flex flex-col divide-y divide-notion-divider"
        >
          <.empty_state
            id="inbox-empty"
            class="hidden only:block"
            icon="📥"
            title="Your inbox is clear"
          >
            No conversations yet. Start one from a page or the chat panel.
          </.empty_state>

          <.link
            :for={{dom_id, conversation} <- @streams.conversations}
            id={dom_id}
            navigate={~p"/w/#{@workspace.slug}"}
            class="flex items-center gap-3 py-3 px-2 rounded hover:bg-notion-sidebar-hover no-underline"
          >
            <span class={[
              "inline-flex items-center justify-center size-8 rounded-full shrink-0",
              host_badge_class(conversation.host_type)
            ]}>
              <.icon name={host_icon(conversation.host_type)} class="size-4" />
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-notion-text truncate">
                {conversation_title(conversation)}
              </p>
              <p class="text-xs text-notion-text-light truncate">
                {host_context(conversation.host_type)}
              </p>
            </div>
            <span class="text-xs text-notion-text-light shrink-0">
              {relative_time(conversation.updated_at)}
            </span>
          </.link>
        </div>
      </div>
    </Layouts.workspace>
    """
  end

  defp conversation_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp conversation_title(_), do: "Untitled conversation"

  defp host_context(:page), do: "About a page"
  defp host_context(:workspace), do: "About this workspace"
  defp host_context(host_type), do: "About a #{host_type}"

  defp host_icon(:page), do: "hero-document-text-micro"
  defp host_icon(:workspace), do: "hero-sparkles-micro"
  defp host_icon(_), do: "hero-cube-micro"

  defp host_badge_class(:page), do: "bg-notion-sidebar text-notion-text"
  defp host_badge_class(_), do: "bg-notion-blue/10 text-notion-blue"

  defp relative_time(nil), do: ""

  defp relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp relative_time(_), do: ""
end
