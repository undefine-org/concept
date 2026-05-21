defmodule ConceptWeb.BlockRender do
  @moduledoc """
  Function component that dispatches per block type to its renderer.

  * text / composite paths render in-module (legacy paths, not yet migrated).
  * Interactive types (`live_component?/0 == true`) render via
    `<.live_component module={mod} ...>`.
  * All other types delegate to `mod.render(assigns)` where `mod` implements
    `Concept.Pages.BlockType`.
  """
  use Phoenix.Component

  import Phoenix.HTML

  alias Concept.Pages.BlockTypes

  @text_types ~w(
    paragraph heading_1 heading_2 heading_3 quote
    callout to_do bulleted_list_item numbered_list_item code toggle
    table_cell column
  )

  attr :block, :map, required: true
  attr :locked_by, :map, default: nil
  attr :locked_blocks, :map, default: %{}
  attr :current_user, :map, default: nil

  def block(assigns) do
    assigns = assign(assigns, :type, to_string(assigns.block.type))

    cond do
      assigns.type == "table" ->
        composite_table(assigns)

      assigns.type == "columns" ->
        composite_columns(assigns)

      assigns.type in @text_types ->
        text_block(assigns)

      true ->
        custom_block(assigns)
    end
  end

  defp custom_block(assigns) do
    mod = BlockTypes.lookup(assigns.block.type)
    assigns = assign(assigns, :mod, mod)

    if function_exported?(mod, :live_component?, 0) and mod.live_component?() do
      ~H"""
      <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
        <.live_component
          module={@mod}
          id={"ai-" <> @block.id}
          block={@block}
          current_user={@current_user}
        />
      </div>
      """
    else
      ~H"""
      <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
        {@mod.render(assigns)}
      </div>
      """
    end
  end

  defp text_block(assigns) do
    ~H"""
    <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
      <div
        class="ora-block-row group"
        data-block-id={@block.id}
        data-locked-by={@locked_by && @locked_by.user_id}
        style={@locked_by && "--lock-color: #{@locked_by.color}"}
      >
        <ora-block-handle class="ora-block-handle group-hover:opacity-100" block-id={@block.id} />
        <ora-block
          phx-hook="BlockEditor"
          phx-update="ignore"
          id={"b-#{@block.id}"}
          block-id={@block.id}
          block-type={@type}
          initial-content={Jason.encode!(@block.content)}
          placeholder={placeholder_for(@block.type)}
          class="ora-block-host"
        >
          <div data-editor class={ora_block_class(@type)}>
            {raw(Concept.Lexical.to_html(@block.content))}
          </div>
        </ora-block>
      </div>
    </div>
    """
  end

  defp composite_table(assigns) do
    rows = get_in(assigns.block.props, ["rows"]) || 0
    cols = get_in(assigns.block.props, ["cols"]) || 0
    cells = composite_children(assigns.block)

    grid =
      Enum.chunk_every(
        Enum.sort_by(cells, fn c ->
          {get_in(c.props, ["row_index"]) || 0, get_in(c.props, ["col_index"]) || 0}
        end),
        max(cols, 1)
      )

    assigns = assign(assigns, rows: rows, cols: cols, grid: grid)

    ~H"""
    <div
      id={"block-" <> @block.id}
      class="block-anchor scroll-mt-20 ora-composite-table"
      data-block-id={@block.id}
      data-composite-parent="table"
      data-rows={@rows}
      data-cols={@cols}
    >
      <table class="ora-table border-collapse w-full">
        <tbody>
          <tr :for={row <- @grid} class="ora-table-row">
            <td :for={cell <- row} class="ora-table-cell border border-notion-divider align-top p-1">
              <.block
                block={cell}
                locked_by={@locked_blocks[cell.id]}
                locked_blocks={@locked_blocks}
                current_user={@current_user}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp composite_columns(assigns) do
    children =
      assigns.block
      |> composite_children()
      |> Enum.sort_by(& &1.position)

    count = get_in(assigns.block.props, ["count"]) || length(children)
    assigns = assign(assigns, children: children, count: count)

    ~H"""
    <div
      id={"block-" <> @block.id}
      class="block-anchor scroll-mt-20 ora-composite-columns"
      data-block-id={@block.id}
      data-composite-parent="columns"
      data-count={@count}
    >
      <div class="grid gap-2" style={"grid-template-columns: repeat(#{@count}, minmax(0, 1fr));"}>
        <div :for={child <- @children} class="ora-column" data-block-id={child.id}>
          <.block
            block={child}
            locked_by={@locked_blocks[child.id]}
            locked_blocks={@locked_blocks}
            current_user={@current_user}
          />
        </div>
      </div>
    </div>
    """
  end

  defp composite_children(%{children: %Ash.NotLoaded{}}), do: []
  defp composite_children(%{children: nil}), do: []
  defp composite_children(%{children: children}) when is_list(children), do: children
  defp composite_children(_), do: []

  defp ora_block_class("heading_1"), do: "ora-block h1"
  defp ora_block_class("heading_2"), do: "ora-block h2"
  defp ora_block_class("heading_3"), do: "ora-block h3"
  defp ora_block_class(_), do: "ora-block"

  defp placeholder_for(:paragraph), do: "Type something…"
  defp placeholder_for(:heading_1), do: "Heading 1"
  defp placeholder_for(:heading_2), do: "Heading 2"
  defp placeholder_for(:heading_3), do: "Heading 3"
  defp placeholder_for(:quote), do: "Quote"
  defp placeholder_for(:callout), do: "Callout"
  defp placeholder_for(:to_do), do: "To-do"
  defp placeholder_for(:bulleted_list_item), do: "List"
  defp placeholder_for(:numbered_list_item), do: "List"
  defp placeholder_for(:code), do: "Code"
  defp placeholder_for(:toggle), do: "Toggle"
  defp placeholder_for(_), do: ""
end
