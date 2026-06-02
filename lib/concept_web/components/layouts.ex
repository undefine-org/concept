defmodule ConceptWeb.Layouts do
  @moduledoc """
  Layout function components for the Concept application.

  Two top-level shells are exposed:

    * `app/1` — narrow centered shell used by marketing/home and any
      future settings-style pages. Renders the brand bar, then the
      slot inside a max-width container.

    * `shell/1` — full-bleed shell used by the workspace. No top
      chrome (the sidebar is the chrome); just renders the slot
      across the full viewport and mounts the flash group.

  Both call `flash_group/1` so toasts surface no matter which shell
  the route uses.
  """
  use ConceptWeb, :html

  import ConceptWeb.Components.Sidebar

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @doc """
  Marketing / auth-style shell. Brand bar across the top, then a
  centered content column.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current user/workspace scope"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="ora-app-header">
      <a href={~p"/"} class="ora-app-header__brand">
        <span class="ora-app-header__mark" aria-hidden="true">C</span>
        <span>
          Concept{if @current_scope && @current_scope.workspace,
            do: " / " <> to_string(@current_scope.workspace.name)}
        </span>
      </a>
      <div class="ora-app-header__actions">
        <%= if @current_scope do %>
          <details class="relative">
            <summary class="ora-avatar list-none">
              {@current_scope.user.email |> to_string() |> String.first() |> String.upcase()}
            </summary>
            <div class="ora-menu">
              <div class="ora-menu__title">{@current_scope.user.email}</div>
              <a class="ora-menu__item" href={~p"/w"}>Dashboard</a>
              <.link class="ora-menu__item" href={~p"/sign-out"} method="delete">Sign out</.link>
            </div>
          </details>
        <% else %>
          <.link navigate={~p"/sign-in"} class="ora-btn ora-btn--ghost">Sign in</.link>
          <.link navigate={~p"/register"} class="ora-btn ora-btn--primary">Get started</.link>
        <% end %>
      </div>
    </header>

    <main class="mx-auto max-w-2xl px-6 py-12 space-y-4">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Full-bleed shell used by the workspace. The page itself owns the
  layout (sidebar + canvas); we just mount the flash group on top.
  """
  attr :flash, :map, required: true

  attr :current_scope, :map,
    default: nil,
    doc: "currently unused but kept to mirror app/1's signature"

  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <main class="min-h-screen bg-notion-bg">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Unified authed workspace shell. Every signed-in surface (page editor,
  board, work, inbox, graph) renders through this one component so they
  share identical chrome: the sidebar on desktop, a slide-in drawer on
  mobile, and a single place to evolve navigation.

  The page supplies its canvas via the default slot; cross-cutting
  overlays (chat panel, command palette, modals, rails) go in the
  optional `:overlays` slot so they sit as siblings of the flex row,
  not inside `<main>`.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :workspace, :map, required: true
  attr :current_user, :map, required: true
  attr :pages, :list, default: []
  attr :current_page, :map, default: nil
  attr :live_rail_show, :boolean, default: false
  attr :unread_count, :integer, default: 0
  attr :id, :string, default: "workspace-root"

  attr :hook, :string,
    default: "GlobalKeys",
    doc: "phx-hook(s) on the flex root; pass extra hooks space-separated"

  slot :inner_block, required: true
  slot :overlays, doc: "panels/modals/rails rendered as siblings of the flex row"

  def workspace(assigns) do
    ~H"""
    <.shell flash={@flash} current_scope={@current_scope}>
      <div id={@id} class="ora-ws-root flex min-h-screen" phx-hook={@hook}>
        <%!-- Mobile top bar: only shows < md. Hamburger toggles the drawer
              purely client-side (no round-trip), overlay dims the canvas. --%>
        <header class="ora-mobile-bar md:hidden">
          <button
            type="button"
            class="ora-mobile-bar__btn"
            aria-label="Open navigation"
            phx-click={
              JS.remove_class("-translate-x-full", to: "#ws-drawer")
              |> JS.remove_class("hidden", to: "#ws-drawer-scrim")
            }
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <span class="ora-mobile-bar__title truncate">
            <span aria-hidden="true">{@workspace.icon_emoji || "🏠"}</span>
            <span class="truncate">{@workspace.name}</span>
          </span>
        </header>

        <div
          id="ws-drawer-scrim"
          class="ora-drawer-scrim hidden md:hidden"
          phx-click={
            JS.add_class("-translate-x-full", to: "#ws-drawer")
            |> JS.add_class("hidden", to: "#ws-drawer-scrim")
          }
        >
        </div>

        <div id="ws-drawer" class="ora-drawer -translate-x-full md:translate-x-0">
          <.sidebar
            workspace={@workspace}
            pages={@pages}
            current_page={@current_page}
            current_user={@current_user}
            live_rail_show={@live_rail_show}
            unread_count={@unread_count}
          />
        </div>

        <main class="flex-1 overflow-y-auto bg-notion-bg ora-workspace-main">
          {render_slot(@inner_block)}
        </main>

        {render_slot(@overlays)}
      </div>
    </.shell>
    """
  end

  @doc """
  Renders the flash group (info / error / warning) plus the
  client-error / server-error reconnection pills.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="ora-flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
