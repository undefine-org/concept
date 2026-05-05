defmodule Concept.Pages.Notifiers.KnowledgeReindex do
  @moduledoc """
  Ash.Notifier that schedules a re-ingest job when pages or blocks change.
  Implements debounced per-page reindexing via AshOban.
  """
  use Ash.Notifier

  @impl true
  def notify(notification) do
    # Stub — will be wired in FEAT-022::notifier
    {:ok, notification}
  end
end
