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
        <img src={~p"/images/logo.svg"} width="24" height="24" alt="" />
        <span>Concept{if @current_scope && @current_scope.workspace,
              do: " / " <> to_string(@current_scope.workspace.name)}</span>
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
