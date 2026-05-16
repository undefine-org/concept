defmodule Concept.Knowledge.Changes.MirrorToArcanaGraph do
  @moduledoc """
  Mirrors Knowledge.Link create/destroy actions into Arcana.Graph.Relationship rows.

  User-defined links are prefixed with "USER_" to distinguish them from
  structural relationships (CONTAINS, PARENT_OF, HAS_TYPE) built by GraphBuilder.
  """
  use Ash.Resource.Change
  require Logger
  import Ecto.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    case changeset.action.type do
      :create -> Ash.Changeset.after_action(changeset, &after_create/2)
      :destroy -> Ash.Changeset.before_action(changeset, &before_destroy/1)
      _ -> changeset
    end
  end

  defp after_create(_changeset, link) do
    rel_type = "USER_" <> (link.kind |> Atom.to_string() |> String.upcase())

    attrs = %{
      source_id: link.source_block_id,
      target_id: link.target_block_id,
      type: rel_type,
      description: link.note,
      strength: 1,
      metadata: %{
        "link_id" => link.id,
        "workspace_id" => link.workspace_id,
        "created_by" => link.created_by_user_id
      }
    }

    # No unique index on (source_id, target_id, type), so use get_by + insert_or_update
    case Concept.Repo.get_by(Arcana.Graph.Relationship,
           source_id: link.source_block_id,
           target_id: link.target_block_id,
           type: rel_type
         ) do
      nil ->
        %Arcana.Graph.Relationship{}
        |> Arcana.Graph.Relationship.changeset(attrs)
        |> Concept.Repo.insert()

      existing ->
        existing
        |> Arcana.Graph.Relationship.changeset(attrs)
        |> Concept.Repo.update()
    end
    |> case do
      {:ok, _} ->
        {:ok, link}

      {:error, e} ->
        Logger.warning("Knowledge.Link mirror failed: #{inspect(e)}")
        {:ok, link}
    end
  end

  defp before_destroy(changeset) do
    link = changeset.data
    rel_type = "USER_" <> (link.kind |> Atom.to_string() |> String.upcase())

    Concept.Repo.delete_all(
      from r in Arcana.Graph.Relationship,
        where:
          r.source_id == ^link.source_block_id and
            r.target_id == ^link.target_block_id and
            r.type == ^rel_type
    )

    changeset
  end
end
