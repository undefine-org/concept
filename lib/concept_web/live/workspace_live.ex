defmodule ConceptWeb.WorkspaceLive do
  @moduledoc "Workspace shell — see FEAT-005."
  use ConceptWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :placeholder, true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8 text-notion-text-light">Workspace shell — wiring in progress (FEAT-005).</div>
    """
  end
end
