defmodule ConceptWeb.Components.CoverBand do
  @moduledoc "Cover band function component — maps color atom to gradient CSS class."
  use ConceptWeb, :html

  attr :color, :atom, default: :default
  attr :rest, :global

  def cover_band(assigns) do
    ~H"""
    <%= if @color == :default do %>
      <div class="ora-cover-default" {@rest}>
        <button type="button" class="ora-cover-add">+ Add cover</button>
      </div>
    <% else %>
      <div class={["ora-cover", "ora-cover-#{@color}"]}></div>
    <% end %>
    """
  end
end
