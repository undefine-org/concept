defmodule Concept.Objects.Record.Preparations.FilterReady do
  @moduledoc """
  Narrow a record query to those *ready to pick up*:

    ready?(r) := r.state.category == :todo
               ∧ ¬ blocked?(r)   (see `Concept.Objects.Record.Blocking`)

  The base action filter already excludes assigned records. Here we add the
  `:todo` category constraint (SQL, via the `state` relationship) and then
  prune records that still have an incomplete `blocked_by` dependency — the
  blocking predicate is shared with the board/work UI via `Record.Blocking`
  so "blocked" has exactly one definition.
  """
  use Ash.Resource.Preparation
  require Ash.Query

  alias Concept.Objects.Record.Blocking

  @impl true
  def prepare(query, _opts, _ctx) do
    query
    |> Ash.Query.filter(exists(state, category == :todo))
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.after_action(&prune_blocked/2)
  end

  defp prune_blocked(query, records) do
    blocked = Blocking.blocked_ids(records, query.tenant)
    {:ok, Enum.reject(records, &MapSet.member?(blocked, &1.id))}
  end
end
