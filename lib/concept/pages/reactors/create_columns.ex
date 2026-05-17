defmodule Concept.Pages.Reactors.CreateColumns do
  @moduledoc """
  Atomic creation of a Columns parent block + N Column children.

  Steps:
    1. `create_parent` — inserts the Columns parent block.
    2. `create_children` — inserts `count` Column children inside a
       `Concept.Repo.transaction/1`. On failure, transaction rolls back
       and Reactor invokes `undo` on `create_parent`, archiving it.
  """
  use Reactor

  alias Concept.Pages

  input :workspace_id
  input :page_id
  input :count
  input :actor
  input :position

  step :create_parent do
    argument :workspace_id, input(:workspace_id)
    argument :page_id, input(:page_id)
    argument :count, input(:count)
    argument :actor, input(:actor)
    argument :position, input(:position)

    run fn args, _ctx ->
      ratio = 1.0 / args.count

      props = %{
        "count" => args.count,
        "ratios" => List.duplicate(ratio, args.count)
      }

      attrs =
        case args.position do
          nil -> %{props: props}
          pos when is_binary(pos) -> %{props: props, position: pos}
        end

      Pages.create_block(
        args.page_id,
        :columns,
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

  step :create_children do
    argument :parent, result(:create_parent)
    argument :workspace_id, input(:workspace_id)
    argument :page_id, input(:page_id)
    argument :count, input(:count)
    argument :actor, input(:actor)

    run fn args, _ctx ->
      ratio = 1.0 / args.count
      indices = Enum.to_list(0..(args.count - 1))

      Concept.Repo.transaction(fn ->
        result =
          Enum.reduce_while(indices, [], fn idx, acc ->
            child_props = %{"ratio" => ratio, "col_index" => idx}

            case Pages.create_block(
                   args.page_id,
                   :column,
                   args.workspace_id,
                   args.parent.id,
                   %{props: child_props},
                   actor: args.actor,
                   tenant: args.workspace_id
                 ) do
              {:ok, col} -> {:cont, [col | acc]}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case result do
          {:error, reason} -> Concept.Repo.rollback(reason)
          cols when is_list(cols) -> Enum.reverse(cols)
        end
      end)
    end

    undo fn cols, args, _ctx ->
      Enum.each(cols, fn col ->
        Pages.archive_block(col, actor: args.actor, tenant: args.workspace_id)
      end)

      :ok
    end
  end

  return :create_parent
end
