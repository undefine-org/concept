defmodule Concept.Pages do
  @moduledoc "Page tree + Block content domain."
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain, AshAi]

  admin do
    show? true
  end

  tools do
    tool :create_page, Concept.Pages.Page, :create_page do
      description "Create a new page under the given parent (or top-level)."
    end
  end

  resources do
    resource Concept.Pages.Page do
      define :create_page, args: [:title, :workspace_id, {:optional, :parent_page_id}]
      define :rename_page, args: [:title], action: :rename
      define :set_icon, args: [:icon_emoji]
      define :set_cover_color, args: [:cover_color]
      define :reorder, args: [:position]
      define :reparent, args: [:parent_page_id, :position]
      define :archive
      define :restore
      define :list_tree, action: :list_tree
      define :recent_pages, action: :recent_pages
      define :search_titles, args: [:query]
      define :get_page, action: :read, get_by: :id
    end

    resource Concept.Pages.Block do
      define :create_block, args: [:page_id, :type, :workspace_id, {:optional, :parent_block_id}]
      define :update_content, args: [:content]
      define :update_props, args: [:props]
      define :evaluate_ai, args: [:prompt, {:optional, :scope}, {:optional, :profile}]
      define :reorder_block, args: [:position], action: :reorder
      define :reparent_block, args: [:parent_block_id, :position], action: :reparent
      define :archive_block, action: :archive
      define :acquire_lock
      define :release_lock
      define :refresh_lock
      define :list_for_page, args: [:page_id]
    end
  end

  @doc """
  Atomically create a Table parent + rows*cols TableCell children.

  Returns `{:ok, parent}` on success, `{:error, reason}` if any insert
  fails (parent and partial cells rolled back).
  """
  def create_table(workspace_id, page_id, rows, cols, opts)
      when is_integer(rows) and is_integer(cols) and rows > 0 and cols > 0 do
    actor = Keyword.fetch!(opts, :actor)
    position = Keyword.get(opts, :position)

    Reactor.run(
      Concept.Pages.Reactors.CreateTable,
      %{
        workspace_id: workspace_id,
        page_id: page_id,
        rows: rows,
        cols: cols,
        actor: actor,
        position: position
      },
      %{},
      async?: false
    )
  end

  @doc """
  Atomically create a Columns parent + N Column children.

  Returns `{:ok, parent}` on success, `{:error, reason}` on failure.
  """
  def create_columns(workspace_id, page_id, count, opts)
      when is_integer(count) and count > 0 do
    actor = Keyword.fetch!(opts, :actor)
    position = Keyword.get(opts, :position)

    Reactor.run(
      Concept.Pages.Reactors.CreateColumns,
      %{
        workspace_id: workspace_id,
        page_id: page_id,
        count: count,
        actor: actor,
        position: position
      },
      %{},
      async?: false
    )
  end

  @doc """
  Computes staleness for an `:ai_answer` block.

  Returns `%{stale?: boolean, drifted_count: integer, drifted_block_ids: [uuid]}`.

  A block is stale if any cited block has `updated_at > Message.inserted_at`.
  Defensive: returns `%{stale?: false, drifted_count: 0, drifted_block_ids: []}` if
  the block has no message_id or if citations/blocks cannot be loaded.
  """
  def staleness_for_ai_block(block) do
    message_id = get_in(block.content, ["message_id"])
    workspace_id = block.workspace_id
    system_actor = %{system?: true}

    if is_nil(message_id) do
      %{stale?: false, drifted_count: 0, drifted_block_ids: []}
    else
      with {:ok, message} <- load_message(message_id, system_actor),
           {:ok, citations} <-
             Concept.Knowledge.citations_for_message(message_id,
               actor: system_actor,
               tenant: workspace_id
             ),
           {:ok, blocks} <- load_cited_blocks(citations, system_actor, workspace_id) do
        compute_staleness(blocks, message.inserted_at)
      else
        _ -> %{stale?: false, drifted_count: 0, drifted_block_ids: []}
      end
    end
  end

  defp load_message(message_id, actor) do
    Concept.Knowledge.Chat.Message
    |> Ash.get(message_id, actor: actor, authorize?: false)
  end

  defp load_cited_blocks(citations, actor, workspace_id) do
    block_ids = Enum.map(citations, & &1.block_id)

    if Enum.empty?(block_ids) do
      {:ok, []}
    else
      import Ash.Query

      Concept.Pages.Block
      |> filter(id in ^block_ids)
      |> Ash.read(actor: actor, tenant: workspace_id, authorize?: false)
    end
  end

  defp compute_staleness(blocks, message_inserted_at) do
    drifted =
      blocks
      |> Enum.filter(fn block ->
        DateTime.compare(block.updated_at, message_inserted_at) == :gt
      end)

    %{
      stale?: length(drifted) > 0,
      drifted_count: length(drifted),
      drifted_block_ids: Enum.map(drifted, & &1.id)
    }
  end
end
