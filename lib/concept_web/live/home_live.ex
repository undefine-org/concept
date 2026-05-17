defmodule ConceptWeb.HomeLive do
  @moduledoc "Public landing — proves Phoenix + Lit pipeline are live."
  use ConceptWeb, :live_view

  on_mount {ConceptWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, socket}

      user ->
        case Concept.Accounts.get_primary_workspace(user, actor: user) do
          {:ok, %{slug: slug}} ->
            {:ok, Phoenix.LiveView.push_navigate(socket, to: ~p"/w/#{slug}")}

          _ ->
            {:ok, socket}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="home-root"
        phx-hook="GlobalKeys"
        class="min-h-screen bg-white flex flex-col items-center justify-center gap-8 px-6"
      >
        <div class="text-center space-y-4 max-w-xl">
          <div class="text-6xl">📝</div>
          <h1
            class="text-5xl font-bold tracking-tight"
            style="font-family: Inter, system-ui, sans-serif;"
          >
            Concept
          </h1>
          <p class="text-lg text-notion-text-light">
            A pixel-perfect, Ash-powered Notion clone. Lit + Lexical blocks, real-time collaboration, paragraph-level locks.
          </p>
          <div class="pt-2">
            <ora-hello data-testid="ora-hello"></ora-hello>
          </div>
        </div>
        <div class="flex gap-3 pt-2">
          <%= if @current_user do %>
            <.link
              navigate={~p"/w"}
              class="px-4 py-2 bg-notion-text text-white rounded-md font-medium"
              data-testid="enter-workspace"
            >
              Enter your workspace →
            </.link>
            <.link
              href={~p"/sign-out"}
              method="delete"
              class="px-4 py-2 border border-notion-divider rounded-md font-medium"
            >
              Sign out
            </.link>
          <% else %>
            <.link
              navigate={~p"/register"}
              class="px-4 py-2 bg-notion-text text-white rounded-md font-medium"
              data-testid="get-started"
            >
              Get started
            </.link>
            <.link
              navigate={~p"/sign-in"}
              class="px-4 py-2 border border-notion-divider rounded-md font-medium"
            >
              Sign in
            </.link>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # GlobalKeys hook (BUG-025) — Cmd-K opens the command palette. HomeLive has
  # no palette UI of its own; for a signed-in user we forward to /w (which
  # then resolves the primary workspace), and for signed-out users we no-op
  # rather than crash on a missing handler.
  @impl true
  def handle_event("open_command_palette", _params, socket) do
    case socket.assigns[:current_user] do
      nil -> {:noreply, socket}
      _user -> {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/w")}
    end
  end

  def handle_event("close_command_palette", _params, socket) do
    {:noreply, socket}
  end
end
