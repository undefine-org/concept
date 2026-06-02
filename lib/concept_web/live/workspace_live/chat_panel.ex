defmodule ConceptWeb.WorkspaceLive.ChatPanel do
  @moduledoc """
  ChatPanel — the page-scoped "Chat" peek drawer.

  Wraps `ConceptWeb.ChatComponent` as a slide-in drawer (bottom-right "Chat"
  button + ⌘J toggle from `WorkspaceLive`). When a page is open the rail is
  scoped to that page's host (`rail_scope: :host`), so the drawer is a window
  onto just this page's conversations; otherwise it is workspace-scoped (e.g.
  the palette's "Ask the workspace"). The header "Open in Channels" link
  hands the active conversation off to the full-screen `ChannelsLive` route.
  """
  use ConceptWeb, :live_component
  import ConceptWeb.CoreComponents

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:message_scope, fn -> :workspace end)
      |> assign_new(:message_profile, fn -> :default end)
      |> assign_new(:initial_prompt, fn -> nil end)
      |> assign_new(:conversation_id, fn -> nil end)
      |> assign_new(:current_page, fn -> nil end)
      |> assign_new(:scope_target_id, fn -> nil end)

    {:ok, socket}
  end

  # The peek is page-scoped when a page is open (rail shows only that page's
  # conversations), workspace-scoped otherwise (e.g. opened via the palette's
  # "Ask the workspace"). Both are projections of the same ChatComponent.
  defp peek_host_type(%{current_page: page}) when not is_nil(page), do: :page
  defp peek_host_type(_), do: :workspace

  defp peek_rail_scope(%{current_page: page}) when not is_nil(page), do: :host
  defp peek_rail_scope(_), do: :mine
  @impl true
  def handle_event("close", _params, socket) do
    send(self(), :close_chat_panel)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:peek_host_type, peek_host_type(assigns))
      |> assign(:peek_rail_scope, peek_rail_scope(assigns))

    ~H"""
    <div class={["ora-chat-panel", @open && "ora-chat-panel--open"]}>
      <div class="flex flex-col h-full">
        <div class="ora-chat-header">
          <div class="flex items-center gap-2 min-w-0">
            <.icon
              name={
                if(@current_page,
                  do: "hero-document-text-micro",
                  else: "hero-chat-bubble-left-right-micro"
                )
              }
              class="size-4 text-notion-text-light shrink-0"
            />
            <h2 class="truncate">
              {if @current_page, do: @current_page.title, else: "Chat"}
            </h2>
          </div>
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="ora-btn ora-btn--ghost ora-btn--icon"
            aria-label="Close chat"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>

        <%!-- The peek is a window onto this page's conversations; the full
              team-comms home is the Channels route. Deep-link there, carrying
              the active conversation when one is selected. --%>
        <.link
          navigate={
            if(@conversation_id,
              do: ~p"/w/#{@workspace.slug}/channels/#{@conversation_id}",
              else: ~p"/w/#{@workspace.slug}/channels"
            )
          }
          id="peek-open-in-channels"
          class="ora-btn ora-btn--primary justify-center gap-1.5 mx-3 mt-3 no-underline"
        >
          <span>Open in Channels</span>
          <.icon name="hero-arrow-right-micro" class="size-4" />
        </.link>

        <div class="ora-chat-body flex-1 overflow-hidden">
          <.live_component
            module={ConceptWeb.ChatComponent}
            id={"chat-component-#{@workspace.id}"}
            current_user={@current_user}
            workspace_id={@workspace.id}
            hide_sidebar={false}
            rail_scope={@peek_rail_scope}
            message_scope={@message_scope}
            message_profile={@message_profile}
            initial_prompt={@initial_prompt}
            conversation_id={@conversation_id}
            host_type={@peek_host_type}
            host_id={@current_page && @current_page.id}
            scope_target_id={@scope_target_id}
          />
        </div>
      </div>
    </div>
    """
  end
end
