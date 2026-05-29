defmodule Concept.Objects.Record.Preparations.FilterReady do
  @moduledoc """
  Narrow a record query to those *ready to pick up*:

    ready?(r) := r.state.category == :todo
               ∧ ∀ blocked_by link b: b.to_record.state.category ∈ {:done, :canceled}

  The base action filter already excludes assigned records. Here we add the
  `:todo` category constraint (SQL, via the `state` relationship) and then
  prune records that still have incomplete blockers (post-filter over
  `RecordLink` rows whose `field_def` is a relation key `blocked_by`).
  """
  use Ash.Resource.Preparation
  require Ash.Query

  @done_categories [:done, :canceled]

  @impl true
  def prepare(query, _opts, _ctx) do
    query
    |> Ash.Query.filter(exists(state, category == :todo))
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.after_action(&prune_blocked/2)
  end

  defp prune_blocked(query, records) do
    tenant = query.tenant
    ready = Enum.reject(records, &blocked?(&1, tenant))
    {:ok, ready}
  end

  defp blocked?(record, tenant) do
    links =
      Concept.Objects.RecordLink
      |> Ash.Query.filter(from_record_id == ^record.id)
      |> Ash.Query.set_tenant(tenant)
      |> Ash.read!(authorize?: false)

    blocker_ids =
      links
      |> Enum.filter(&blocked_by_link?(&1, tenant))
      |> Enum.map(& &1.to_record_id)

    case blocker_ids do
      [] ->
        false

      ids ->
        blockers =
          Concept.Objects.Record
          |> Ash.Query.filter(id in ^ids)
          |> Ash.Query.load(:state)
          |> Ash.Query.set_tenant(tenant)
          |> Ash.read!(authorize?: false)

        Enum.any?(blockers, fn b ->
          is_nil(b.state) or b.state.category not in @done_categories
        end)
    end
  end

  # A link counts as a dependency when its field_def key is "blocked_by".
  defp blocked_by_link?(%{field_def_id: nil}, _tenant), do: false

  defp blocked_by_link?(%{field_def_id: fid}, tenant) do
    case Ash.get(Concept.Objects.FieldDef, fid, tenant: tenant, authorize?: false) do
      {:ok, %{key: "blocked_by"}} -> true
      _ -> false
    end
  end
end
