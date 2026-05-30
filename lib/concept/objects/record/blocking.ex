defmodule Concept.Objects.Record.Blocking do
  @moduledoc """
  Single source of truth for record *blocking* semantics.

    blocked?(r) := ∃ link b where b.field_def.key == "blocked_by"
                 ∧ b.to_record.state.category ∉ {:done, :canceled}

  A record is blocked while any of its `blocked_by` dependencies is still in a
  non-terminal state. Both the `:ready` reads (which must *exclude* blocked
  records) and the board/work UI (which must *badge* them) consume this module
  so there is exactly one definition of "blocked".

  `blocked_ids/2` is the batched form — one pair of queries for an arbitrary
  set of records — preferred by callers that already hold a record list (board,
  work view). `blocked?/2` is the single-record convenience used by the
  `FilterReady` post-filter.
  """
  require Ash.Query

  @done_categories [:done, :canceled]

  @doc """
  Given a list of `%Record{}` (or record ids) and a tenant, return the
  `MapSet` of ids that are currently blocked. Resolves `blocked_by` links and
  their target states in two batched reads (no per-record N+1).
  """
  @spec blocked_ids([Concept.Objects.Record.t() | binary()] | [], term()) :: MapSet.t()
  def blocked_ids([], _tenant), do: MapSet.new()

  def blocked_ids(records, tenant) do
    from_ids =
      records
      |> Enum.map(&record_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case from_ids do
      [] ->
        MapSet.new()

      ids ->
        blocked_by_field_ids = blocked_by_field_ids(tenant)

        links =
          Concept.Objects.RecordLink
          |> Ash.Query.filter(from_record_id in ^ids)
          |> Ash.Query.set_tenant(tenant)
          |> Ash.read!(authorize?: false)
          |> Enum.filter(&MapSet.member?(blocked_by_field_ids, &1.field_def_id))

        incomplete = incomplete_blocker_ids(links, tenant)

        for link <- links,
            MapSet.member?(incomplete, link.to_record_id),
            into: MapSet.new(),
            do: link.from_record_id
    end
  end

  @doc "True when the single `record` has an incomplete `blocked_by` dependency."
  @spec blocked?(Concept.Objects.Record.t(), term()) :: boolean()
  def blocked?(record, tenant) do
    record |> record_id() |> List.wrap() |> blocked_ids(tenant) |> MapSet.size() > 0
  end

  # ── internals ──────────────────────────────────────────────────────────

  defp record_id(%{id: id}), do: id
  defp record_id(id) when is_binary(id), do: id
  defp record_id(_), do: nil

  # Field defs whose key is "blocked_by" — these realize dependency edges.
  defp blocked_by_field_ids(tenant) do
    Concept.Objects.FieldDef
    |> Ash.Query.filter(key == "blocked_by")
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.id)
  end

  # Of the link targets, which are still in a non-terminal state (= incomplete).
  defp incomplete_blocker_ids(links, tenant) do
    target_ids = links |> Enum.map(& &1.to_record_id) |> Enum.uniq()

    case target_ids do
      [] ->
        MapSet.new()

      ids ->
        Concept.Objects.Record
        |> Ash.Query.filter(id in ^ids)
        |> Ash.Query.load(:state)
        |> Ash.Query.set_tenant(tenant)
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&incomplete?/1)
        |> MapSet.new(& &1.id)
    end
  end

  defp incomplete?(%{state: state}) do
    is_nil(state) or state.category not in @done_categories
  end
end
