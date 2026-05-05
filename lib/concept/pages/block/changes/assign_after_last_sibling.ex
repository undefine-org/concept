defmodule Concept.Pages.Block.Changes.AssignAfterLastSibling do
  @moduledoc "Compute default position as after-last-sibling within (page, parent_block)."
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
        page_id = Ash.Changeset.get_attribute(changeset, :page_id)
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_block_id)

        query =
          Concept.Pages.Block
          |> Ash.Query.filter(page_id == ^page_id)
          |> Ash.Query.sort(position: :desc)
          |> Ash.Query.limit(1)
          |> Ash.Query.set_tenant(tenant)

        query =
          if is_nil(parent_id),
            do: Ash.Query.filter(query, is_nil(parent_block_id)),
            else: Ash.Query.filter(query, parent_block_id == ^parent_id)

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
end
