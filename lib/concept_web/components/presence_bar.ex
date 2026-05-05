defmodule ConceptWeb.Components.PresenceBar do
  @moduledoc "Horizontal avatar bar showing active collaborators on a page."
  use ConceptWeb, :html

  attr :users, :list, default: []

  def presence_bar(assigns) do
    ~H"""
    <div :if={@users != []} class="flex items-center gap-2 px-4 py-2">
      <span class="text-xs text-notion-text-light mr-1">Active</span>
      <div :for={u <- @users} class="flex items-center gap-1.5">
        <div
          class="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold text-white"
          style={"background-color: #{u.color};"}
          title={u.display_name}
        >
          {u.display_name |> String.first() |> String.upcase()}
        </div>
      </div>
    </div>
    """
  end
end
