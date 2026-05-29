defmodule ConceptWeb.Components.PageHeader do
  @moduledoc "Page header live component: cover band, emoji picker, editable title."
  use ConceptWeb, :live_component

  import ConceptWeb.Components.CoverBand, only: [cover_band: 1]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, show_emoji_picker: false, show_cover_picker: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ora-page-header" phx-hook="PageHeader" phx-target={@myself}>
      <.cover_band
        color={@page.cover_color}
        phx-click="toggle_cover_picker"
        phx-target={@myself}
      />

      <div class="ora-page-header-meta">
        <button
          type="button"
          class="ora-page-emoji-btn"
          phx-click="toggle_emoji_picker"
          phx-target={@myself}
        >
          {@page.icon_emoji || "📄"}
        </button>

        <%= if @show_emoji_picker do %>
          <div
            class="ora-emoji-picker-popover"
            phx-click-away="close_emoji_picker"
            phx-target={@myself}
          >
            <ora-emoji-picker
              phx-hook="EmojiPicker"
              phx-target={@myself}
              id={"emoji-picker-#{@page.id}"}
            />
          </div>
        <% end %>
      </div>

      <h1
        id={"page-title-#{@page.id}"}
        class="ora-page-title"
        contenteditable="true"
        phx-hook="ContentEditable"
        phx-target={@myself}
        phx-update="ignore"
        data-title={@page.title || ""}
        data-placeholder="Untitled"
      ><%= @page.title || "" %></h1>

      <%= if @show_cover_picker do %>
        <div
          class="ora-cover-picker-popover"
          phx-click-away="close_cover_picker"
          phx-target={@myself}
        >
          <%= for color <- ~w(default red orange yellow green blue purple pink gray)a do %>
            <button
              type="button"
              class={"ora-cover-swatch ora-cover-swatch-#{color}"}
              phx-click="set_cover_color"
              phx-value-color={color}
              phx-target={@myself}
              aria-label={"Set cover color #{color}"}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_emoji_picker", _params, socket) do
    {:noreply, update(socket, :show_emoji_picker, &not/1)}
  end

  @impl true
  def handle_event("close_emoji_picker", _params, socket) do
    {:noreply, assign(socket, :show_emoji_picker, false)}
  end

  @impl true
  def handle_event("toggle_cover_picker", _params, socket) do
    {:noreply, update(socket, :show_cover_picker, &not/1)}
  end

  @impl true
  def handle_event("close_cover_picker", _params, socket) do
    {:noreply, assign(socket, :show_cover_picker, false)}
  end

  @impl true
  def handle_event("set_emoji", %{"emoji" => emoji}, socket) do
    page = socket.assigns.page
    user = socket.assigns.current_user

    case Concept.Pages.set_icon(page, emoji, actor: user, tenant: page.workspace_id) do
      {:ok, updated_page} ->
        {:noreply,
         socket
         |> assign(:page, updated_page)
         |> assign(:show_emoji_picker, false)}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_cover_color", %{"color" => color}, socket) do
    page = socket.assigns.page
    user = socket.assigns.current_user
    color_atom = String.to_existing_atom(color)

    case Concept.Pages.set_cover_color(page, color_atom, actor: user, tenant: page.workspace_id) do
      {:ok, updated_page} ->
        {:noreply,
         socket
         |> assign(:page, updated_page)
         |> assign(:show_cover_picker, false)}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_title", %{"value" => value}, socket) do
    page = socket.assigns.page
    user = socket.assigns.current_user

    case Concept.Pages.rename_page(page, value, actor: user, tenant: page.workspace_id) do
      {:ok, updated_page} ->
        {:noreply, assign(socket, :page, updated_page)}

      {:error, _error} ->
        {:noreply, socket}
    end
  end
end
