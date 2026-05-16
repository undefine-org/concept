defmodule Concept.Knowledge.IngestionJob.Changes.IncrementAttempt do
  @moduledoc "Increments the attempt counter for retry tracking."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    current_attempt = Ash.Changeset.get_attribute(changeset, :attempt) || 0
    Ash.Changeset.change_attribute(changeset, :attempt, current_attempt + 1)
  end
end
