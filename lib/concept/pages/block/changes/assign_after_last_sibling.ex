defmodule Concept.Pages.Block.Changes.AssignAfterLastSibling do
  @moduledoc "Compute default position as after-last-sibling within (container, parent_block)."
  use Ash.Resource.Change
  alias Concept.Pages.FractionalIndex
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :position) do
      pos when is_binary(pos) and pos != "" ->
        changeset

      _ ->
        tenant = changeset.tenant || Ash.Changeset.get_attribute(changeset, :workspace_id)
        container_type = Ash.Changeset.get_attribute(changeset, :container_type)
        container_id = Ash.Changeset.get_attribute(changeset, :container_id)
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_block_id)

        # A block lives in exactly one container (container_type/container_id);
        # siblings are scoped to it. AshAI's tool-registry build calls
        # `Ash.can?` with empty input; without a tenant or container we cannot
        # query siblings, so skip (the real action path arrives with both set,
        # or the not-null columns reject it).
        cond_skip = is_nil(tenant) or is_nil(container_type) or is_nil(container_id)

        if cond_skip do
          changeset
        else
          assign_position(changeset, tenant, container_type, container_id, parent_id)
        end
    end
  end

  defp assign_position(changeset, tenant, container_type, container_id, parent_id) do
    base =
      Concept.Pages.Block
      |> Ash.Query.filter(container_type == ^container_type and container_id == ^container_id)
      |> Ash.Query.sort(position: :desc)
      |> Ash.Query.limit(1)
      |> Ash.Query.set_tenant(tenant)

    query =
      if is_nil(parent_id),
        do: Ash.Query.filter(base, is_nil(parent_block_id)),
        else: Ash.Query.filter(base, parent_block_id == ^parent_id)

    last_pos =
      case Ash.read!(query, authorize?: false) do
        [%{position: p} | _] -> p
        _ -> nil
      end

    Ash.Changeset.force_change_attribute(
      changeset,
      :position,
      FractionalIndex.after_(last_pos)
    )
  end
end
