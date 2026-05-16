defmodule Concept.Knowledge.IngestionJob.Changes.SetScheduledAt do
  @moduledoc "Sets scheduled_at to ~2 seconds in the future for debounced processing."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.change_attribute(changeset, :scheduled_at, DateTime.add(DateTime.utc_now(), 2, :second))
  end
end
