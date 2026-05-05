defmodule Concept.Pages.Changes.AssignAfterLastSibling do
  @moduledoc "If `position` is not set, compute it as `after(last_sibling.position)` within the same parent and tenant."
  use Ash.Resource.Change
  alias Concept.Pages.FractionalIndex
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      case Ash.Changeset.get_attribute(cs, :position) do
        pos when is_binary(pos) and pos != "" ->
          cs

        _ ->
          tenant = cs.tenant || Ash.Changeset.get_attribute(cs, :workspace_id)
          parent_id = Ash.Changeset.get_attribute(cs, :parent_page_id)

          query =
            Concept.Pages.Page
            |> Ash.Query.sort(position: :desc)
            |> Ash.Query.limit(1)
            |> Ash.Query.set_tenant(tenant)

          query =
            if is_nil(parent_id),
              do: Ash.Query.filter(query, is_nil(parent_page_id)),
              else: Ash.Query.filter(query, parent_page_id == ^parent_id)

          last_pos =
            case Ash.read!(query, authorize?: false) do
              [%{position: p} | _] -> p
              _ -> nil
            end

          Ash.Changeset.force_change_attribute(cs, :position, FractionalIndex.after_(last_pos))
      end
    end)
  end
end
