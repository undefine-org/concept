defmodule Concept.Objects.Record.Preparations.FilterReady do
  @moduledoc """
  Narrow a record query to those that are *ready to pick up*.

  Wave 1: orders unassigned records (the base filter already excludes
  assigned ones). Wave 3 refines readiness to: state's category is `:todo`
  AND the record has no incomplete `blocked_by` links — derived from
  `WorkflowState.category` and `RecordLink` once those exist.
  """
  use Ash.Resource.Preparation
  require Ash.Query

  @impl true
  def prepare(query, _opts, _ctx) do
    Ash.Query.sort(query, inserted_at: :asc)
  end
end
