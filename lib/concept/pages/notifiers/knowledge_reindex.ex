defmodule Concept.Pages.Notifiers.KnowledgeReindex do
  @moduledoc """
  Ash.Notifier that schedules a re-ingest job when pages or blocks change.
  Implements debounced per-page reindexing via Oban.
  """
  use Ash.Notifier

  require Logger

  @impl true
  def notify(%Ash.Notifier.Notification{resource: Concept.Pages.Page, data: page, action: action}) do
    enqueue(page.workspace_id, "page", page.id, op_for_page(action.name))
    {:ok, page}
  end

  def notify(%Ash.Notifier.Notification{
        resource: Concept.Pages.Block,
        data: block,
        action: %{name: name}
      })
      when name in [:create_block, :update_content, :update_props, :archive, :reparent] do
    # Reparent only moves a block within its container (the action accepts
    # parent_block_id + position, never the container), so a single enqueue of
    # the block's own container source covers every mutating action.
    enqueue_block_source(block)
    {:ok, block}
  end

  def notify(notification), do: {:ok, notification}

  # A block lives in exactly one container (container_type/container_id).
  # Dispatch the ingest to that source. The container_type atom doubles as the
  # ingest source_type string ("page" / "message"); W3 folds this onto
  # Concept.Containable so a new container needs no edit here.
  defp enqueue_block_source(%{container_type: type, container_id: id} = block)
       when is_atom(type) and is_binary(id),
       do: enqueue(block.workspace_id, Atom.to_string(type), id, :upsert)

  defp enqueue_block_source(_block), do: :ok

  defp enqueue(workspace_id, source_type, source_id, op) do
    Concept.Knowledge.Workers.IngestPage.new(
      %{
        workspace_id: workspace_id,
        source_type: source_type,
        source_id: source_id,
        op: op
      },
      scheduled_at: DateTime.add(DateTime.utc_now(), 2, :second),
      unique: [period: 5, fields: [:args], keys: [:source_type, :source_id, :op]]
    )
    |> Oban.insert()
  end

  defp op_for_page(:archive), do: :delete
  defp op_for_page(_), do: :upsert
end
