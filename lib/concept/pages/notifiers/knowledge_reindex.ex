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

  def notify(%Ash.Notifier.Notification{
        resource: Concept.Pages.Block,
        data: block,
        action: %{name: :reparent},
        changeset: cs
      }) do
    # Reparent: ingest both old and new page if block moved across pages.
    # A message-owned block (nil page_id) has no page source to ingest;
    # conversation-source ingestion is handled separately (see maybe_enqueue).
    maybe_enqueue(block.workspace_id, block.page_id, :upsert)

    case Ash.Changeset.get_data(cs, :page_id) do
      nil ->
        :ok

      old_page_id when old_page_id != block.page_id ->
        maybe_enqueue(block.workspace_id, old_page_id, :upsert)

      _ ->
        :ok
    end

    {:ok, block}
  end

  def notify(%Ash.Notifier.Notification{
        resource: Concept.Pages.Block,
        data: block,
        action: %{name: name}
      })
      when name in [:create_block, :update_content, :update_props, :archive] do
    maybe_enqueue(block.workspace_id, block.page_id, op_for_block(name))
    {:ok, block}
  end

  def notify(notification), do: {:ok, notification}

  # Page-source ingestion only fires when the block belongs to a page. A
  # message-owned block (page_id == nil) is ingested via its conversation
  # source by a separate path (PLAN-010 §45); skip the page ingest here rather
  # than enqueue a `page:nil` job.
  defp maybe_enqueue(_workspace_id, nil, _op), do: :ok
  defp maybe_enqueue(workspace_id, page_id, op), do: enqueue(workspace_id, page_id, op)

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

  # Block mutations (incl. archive) re-upsert the page: archived blocks are
  # excluded by Block's archival base_filter, so a fresh page ingest drops them.
  # Page-level deletion is handled by op_for_page(:archive) -> :delete.
  defp op_for_block(_), do: :upsert
end
