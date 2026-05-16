defmodule Concept.Pages.Notifiers.KnowledgeReindex do
  @moduledoc """
  Ash.Notifier that schedules a re-ingest job when pages or blocks change.
  Implements debounced per-page reindexing via Oban.
  """
  use Ash.Notifier

  require Logger

  @impl true
  def notify(%Ash.Notifier.Notification{resource: Concept.Pages.Page, data: page, action: action}) do
    enqueue(page.workspace_id, page.id, op_for_page(action.name))
    {:ok, page}
  end

  def notify(%Ash.Notifier.Notification{resource: Concept.Pages.Block, data: block, action: %{name: :reparent}, changeset: cs}) do
    # Reparent: ingest both old and new page if block moved across pages.
    enqueue(block.workspace_id, block.page_id, :upsert)
    case Ash.Changeset.get_data(cs, :page_id) do
      nil -> :ok
      old_page_id when old_page_id != block.page_id -> enqueue(block.workspace_id, old_page_id, :upsert)
      _ -> :ok
    end
    {:ok, block}
  end

  def notify(%Ash.Notifier.Notification{resource: Concept.Pages.Block, data: block, action: %{name: name}}) when name in [:create_block, :update_content, :update_props, :archive] do
    enqueue(block.workspace_id, block.page_id, op_for_block(name))
    {:ok, block}
  end

  def notify(notification), do: {:ok, notification}

  defp enqueue(workspace_id, page_id, op) do
    Concept.Knowledge.Workers.IngestPage.new(
      %{workspace_id: workspace_id, page_id: page_id, op: op},
      scheduled_at: DateTime.add(DateTime.utc_now(), 2, :second),
      unique: [period: 5, fields: [:args], keys: [:page_id, :op]]
    )
    |> Oban.insert()
  end

  defp op_for_page(:archive), do: :delete
  defp op_for_page(_), do: :upsert

  defp op_for_block(:archive), do: :upsert  # block-archive still ingests; only page-archive deletes
  defp op_for_block(_), do: :upsert
end
