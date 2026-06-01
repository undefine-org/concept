defmodule ConceptWeb.BlockRender do
  @moduledoc """
  Pure dispatcher: routes each block to a render path by its type module's
  `render_kind/0` — the single source of truth declared on the block type.

  | `render_kind/0` | Path |
  |---|---|
  | `:text` | shared `<ora-block>` Lexical host; `placeholder/0` + `editor_class/0` from the module |
  | `:static` | `mod.render/1` |
  | `:interactive` | `<.live_component module={mod} ...>` |
  | `:composite` | shared grid host selected by `mod.composite_layout/0` |

  No hardcoded type lists, no string special-casing. Adding a block type never
  requires editing this module — see `lib/concept/pages/block_types/AGENTS.md`.
  """
  use Phoenix.Component

  import Phoenix.HTML
  import ConceptWeb.CoreComponents, only: [icon: 1]

  alias Concept.Pages.BlockTypes

  attr :block, :map, required: true
  attr :locked_by, :map, default: nil
  attr :locked_blocks, :map, default: %{}
  attr :current_user, :map, default: nil

  def block(assigns) do
    mod = BlockTypes.lookup(assigns.block.type)
    assigns = assign(assigns, mod: mod, type: to_string(assigns.block.type))

    case mod.render_kind() do
      :text -> text_block(assigns)
      :composite -> composite_block(assigns)
      :interactive -> interactive_block(assigns)
      :static -> static_block(assigns)
    end
  end

  defp interactive_block(assigns) do
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
  end

  defp static_block(assigns) do
    ~H"""
    <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
      {@mod.render(assigns)}
    </div>
    """
  end

  defp text_block(assigns) do
    assigns =
      assign(assigns,
        placeholder: assigns.mod.placeholder(),
        editor_class: assigns.mod.editor_class()
      )

    ~H"""
    <div id={"block-" <> @block.id} class="block-anchor scroll-mt-20">
      <div
        class="ora-block-row group"
        data-block-id={@block.id}
        data-locked-by={@locked_by && @locked_by.user_id}
        data-checked={to_string(get_in(@block.props, ["checked"]) == true)}
        style={@locked_by && "--lock-color: #{@locked_by.color}"}
      >
        <%!-- To-do checkbox marker. Clickable only when the block carries a
              `checked` prop (to_do); a no-op decoration otherwise. The type
              module owns its editor_class; this marker is driven by the prop,
              not a hardcoded type check. --%>
        <button
          :if={is_boolean(get_in(@block.props, ["checked"]))}
          type="button"
          class="ora-todo-check"
          phx-click="toggle_check"
          phx-value-block_id={@block.id}
          aria-pressed={to_string(get_in(@block.props, ["checked"]) == true)}
          aria-label="Toggle to-do"
        >
          <.icon
            :if={get_in(@block.props, ["checked"]) == true}
            name="hero-check-micro"
            class="size-3"
          />
        </button>
        <ora-block-handle class="ora-block-handle group-hover:opacity-100" block-id={@block.id} />
        <%!-- C-3: lock is conveyed by a LABEL + tooltip, never colour alone
              (a11y). Screen readers announce who is editing; sighted users get
              a name pill + the coloured rail. --%>
        <span
          :if={@locked_by}
          class="ora-lock-badge"
          style={"--lock-color: #{@locked_by.color}"}
          title={lock_label(@locked_by)}
          aria-label={lock_label(@locked_by)}
        >
          <.icon name="hero-lock-closed-micro" class="size-3" />
          <span class="ora-lock-badge__name">{lock_name(@locked_by)}</span>
        </span>
        <ora-block
          phx-hook="BlockEditor"
          phx-update="ignore"
          id={"b-#{@block.id}"}
          block-id={@block.id}
          block-type={@type}
          initial-content={Jason.encode!(@block.content)}
          placeholder={@placeholder}
          class="ora-block-host"
        >
          <div data-editor class={@editor_class}>
            {raw(Concept.Lexical.to_html(@block.content))}
          </div>
        </ora-block>
      </div>
    </div>
    """
  end

  defp composite_block(assigns) do
    case assigns.mod.composite_layout() do
      :table -> composite_table(assigns)
      :columns -> composite_columns(assigns)
    end
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

  # C-3: humane lock label. Falls back to a generic phrase if the holder's
  # display name isn't known (e.g. presence meta without it).
  defp lock_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp lock_name(_), do: "Someone"

  defp lock_label(locked_by), do: "#{lock_name(locked_by)} is editing this block"

  defp composite_children(%{children: %Ash.NotLoaded{}}), do: []
  defp composite_children(%{children: nil}), do: []
  defp composite_children(%{children: children}) when is_list(children), do: children
  defp composite_children(_), do: []
end
