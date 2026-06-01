defmodule Concept.Pages.Reactors.CreateTable do
  @moduledoc """
  Atomic creation of a Table parent block + rows × cols TableCell children.

  Steps:
    1. `create_parent` — inserts the Table parent block.
    2. `create_cells` — inserts `rows * cols` TableCell children in
       row-major order inside a `Concept.Repo.transaction/1`. If any
       insert fails, the transaction rolls back; the step returns
       `{:error, _}` and Reactor invokes `undo` on `create_parent`,
       archiving the orphaned parent.
  """
  use Reactor

  alias Concept.Pages

  input :workspace_id
  input :page_id
  input :rows
  input :cols
  input :actor
  input :position

  step :create_parent do
    argument :workspace_id, input(:workspace_id)
    argument :page_id, input(:page_id)
    argument :rows, input(:rows)
    argument :cols, input(:cols)
    argument :actor, input(:actor)
    argument :position, input(:position)

    run fn args, _ctx ->
      props = %{
        "rows" => args.rows,
        "cols" => args.cols,
        "has_header_row" => true,
        "column_widths" => List.duplicate(200, args.cols)
      }

      attrs =
        case args.position do
          nil -> %{props: props}
          pos when is_binary(pos) -> %{props: props, position: pos}
        end

      Pages.create_block(
        :page,
        args.page_id,
        :table,
        args.workspace_id,
        nil,
        attrs,
        actor: args.actor,
        tenant: args.workspace_id
      )
    end

    undo fn parent, args, _ctx ->
      case Pages.archive_block(parent, actor: args.actor, tenant: args.workspace_id) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  step :create_cells do
    argument :parent, result(:create_parent)
    argument :workspace_id, input(:workspace_id)
    argument :page_id, input(:page_id)
    argument :rows, input(:rows)
    argument :cols, input(:cols)
    argument :actor, input(:actor)

    run fn args, _ctx ->
      coords = for r <- 0..(args.rows - 1), c <- 0..(args.cols - 1), do: {r, c}

      Concept.Repo.transaction(fn ->
        result =
          Enum.reduce_while(coords, [], fn {r, c}, acc ->
            cell_props = %{"row_index" => r, "col_index" => c}

            case Pages.create_block(
                   :page,
                   args.page_id,
                   :table_cell,
                   args.workspace_id,
                   args.parent.id,
                   %{props: cell_props},
                   actor: args.actor,
                   tenant: args.workspace_id
                 ) do
              {:ok, cell} -> {:cont, [cell | acc]}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case result do
          {:error, reason} -> Concept.Repo.rollback(reason)
          cells when is_list(cells) -> Enum.reverse(cells)
        end
      end)
    end

    undo fn cells, args, _ctx ->
      Enum.each(cells, fn cell ->
        Pages.archive_block(cell, actor: args.actor, tenant: args.workspace_id)
      end)

      :ok
    end
  end

  return :create_parent
end
