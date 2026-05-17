defmodule ConceptWeb.CompositePicker do
  @moduledoc """
  Small rows × cols / column-count picker shown after the slash menu
  selects a composite block type (`:table` or `:columns`).

  The component is purely presentational: each option carries a
  `phx-click="insert_composite_below"` value naming the dimensions and
  the source block to insert below. The host LiveView interprets the
  event (see `ConceptWeb.PageEditorLive`).

  Rendered hidden by default; the `SlashMenu` JS hook reveals it once
  the user selects a composite type from the slash menu by setting
  `data-open="true"` on the wrapping element and writing
  `data-source-block-id` with the block id to insert below.
  """
  use Phoenix.Component

  @max_rows 8
  @max_cols 8
  @column_counts [2, 3, 4]

  attr :id, :string, default: "composite-picker"

  def picker(assigns) do
    assigns =
      assigns
      |> assign(:rows, Enum.to_list(1..@max_rows))
      |> assign(:cols, Enum.to_list(1..@max_cols))
      |> assign(:max_cols, @max_cols)
      |> assign(:column_counts, @column_counts)

    ~H"""
    <div
      id={@id}
      class="ora-composite-picker hidden"
      data-open="false"
      data-mode="table"
      data-source-block-id=""
      role="dialog"
      aria-label="Composite block picker"
    >
      <div
        class="ora-composite-picker-grid p-2 rounded-md bg-white shadow-lg border border-notion-divider"
        data-mode-target="table"
      >
        <div class="text-xs text-notion-text-light mb-1">Pick table size</div>
        <div
          class="grid gap-0.5"
          style={"grid-template-columns: repeat(#{@max_cols}, 1.25rem);"}
        >
          <%= for r <- @rows, c <- @cols do %>
            <button
              type="button"
              class="ora-composite-picker-cell w-5 h-5 border border-notion-divider hover:bg-notion-hover"
              data-rows={r}
              data-cols={c}
              phx-click="insert_composite_below"
              phx-value-type="table"
              phx-value-rows={r}
              phx-value-cols={c}
              aria-label={"#{r} rows by #{c} columns"}
            />
          <% end %>
        </div>
      </div>

      <div
        class="ora-composite-picker-columns p-2 rounded-md bg-white shadow-lg border border-notion-divider hidden"
        data-mode-target="columns"
      >
        <div class="text-xs text-notion-text-light mb-1">Pick column count</div>
        <div class="flex gap-1">
          <button
            :for={n <- @column_counts}
            type="button"
            class="ora-composite-picker-column-btn px-2 py-1 border border-notion-divider hover:bg-notion-hover text-sm"
            data-count={n}
            phx-click="insert_composite_below"
            phx-value-type="columns"
            phx-value-count={n}
            aria-label={"#{n} columns"}
          >
            {n}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
