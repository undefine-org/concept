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
  import ConceptWeb.CoreComponents

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
    <div class={["ora-chat-panel", @open && "ora-chat-panel--open"]}>
      <div class="flex flex-col h-full">
        <div class="ora-chat-header">
          <h2>Chat</h2>
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

        <div class="ora-chat-controls">
          <div>
            <div class="ora-label mb-1">Scope</div>
            <div class="ora-segmented">
              <%= for scope <- [:workspace, :page, :subtree] do %>
                <button
                  type="button"
                  phx-click="set_scope"
                  phx-value-scope={scope}
                  phx-target={@myself}
                  class={[
                    "ora-segmented-btn",
                    @message_scope == scope && "ora-segmented-btn--active"
                  ]}
                >
                  {scope}
                </button>
              <% end %>
            </div>
          </div>

          <div>
            <div class="ora-label mb-1">Profile</div>
            <select
              phx-change="set_profile"
              phx-target={@myself}
              name="profile"
              class="ora-select"
            >
              <%= for profile <- Profiles.list() do %>
                <option value={profile.name} selected={@message_profile == profile.name}>
                  {profile.name} — {profile.description}
                </option>
              <% end %>
            </select>
          </div>
        </div>

        <div class="ora-chat-body flex-1 overflow-hidden">
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
