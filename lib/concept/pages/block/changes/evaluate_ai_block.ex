defmodule Concept.Pages.Block.Changes.EvaluateAiBlock do
  @moduledoc "Change that runs the AI pipeline and writes answer + sources into block content."

  use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context), do: changeset
end
