defmodule ConceptWeb.WorkspaceLive.ChatPanel do
  @moduledoc """
  ChatPanel — workspace chat sidebar with scope + profile controls.

  Wraps ConceptWeb.ChatComponent and adds:
  - Scope selector (workspace/page/subtree)
  - Profile selector (fast/default/thorough/...)
  - ⌘J toggle from parent WorkspaceLive

  Scope+profile values are passed to ChatComponent via assigns and
  included in message creation.
  """
  use ConceptWeb, :live_component

  alias Concept.Knowledge.Profiles

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:message_scope, fn -> :workspace end)
      |> assign_new(:message_profile, fn -> :default end)
      |> assign_new(:initial_prompt, fn -> nil end)
      |> assign_new(:scope_target_id, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_scope", %{"scope" => scope}, socket) do
    {:noreply, assign(socket, :message_scope, String.to_existing_atom(scope))}
  end

  def handle_event("set_profile", %{"profile" => profile}, socket) do
    {:noreply, assign(socket, :message_profile, String.to_existing_atom(profile))}
  end

  def handle_event("close", _params, socket) do
    send(self(), :close_chat_panel)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "ora-chat-panel",
      @open && "ora-chat-panel--open"
    ]}>
      <div class="flex flex-col h-full">
        <!-- Header with close button -->
        <div class="flex items-center justify-between p-4 border-b border-base-300">
          <h2 class="text-lg font-semibold">Chat</h2>
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="btn btn-ghost btn-sm btn-circle"
          >
            ✕
          </button>
        </div>
        
    <!-- Scope + Profile selectors -->
        <div class="p-4 border-b border-base-300 space-y-3">
          <div>
            <label class="label">
              <span class="label-text text-xs font-medium">Scope</span>
            </label>
            <div class="flex gap-2">
              <%= for scope <- [:workspace, :page, :subtree] do %>
                <button
                  type="button"
                  phx-click="set_scope"
                  phx-value-scope={scope}
                  phx-target={@myself}
                  class={[
                    "btn btn-xs",
                    @message_scope == scope && "btn-primary",
                    @message_scope != scope && "btn-outline"
                  ]}
                >
                  {scope}
                </button>
              <% end %>
            </div>
          </div>

          <div>
            <label class="label">
              <span class="label-text text-xs font-medium">Profile</span>
            </label>
            <select
              phx-change="set_profile"
              phx-target={@myself}
              name="profile"
              class="select select-bordered select-sm w-full"
            >
              <%= for profile <- Profiles.list() do %>
                <option value={profile.name} selected={@message_profile == profile.name}>
                  {profile.name} — {profile.description}
                </option>
              <% end %>
            </select>
          </div>
        </div>
        
    <!-- Chat messages (ChatComponent) -->
        <div class="flex-1 overflow-hidden">
          <.live_component
            module={ConceptWeb.ChatComponent}
            id={"chat-component-#{@workspace.id}"}
            current_user={@current_user}
            hide_sidebar={true}
            message_scope={@message_scope}
            message_profile={@message_profile}
            initial_prompt={@initial_prompt}
            scope_target_id={@scope_target_id}
          />
        </div>
      </div>
    </div>
    """
  end
end
