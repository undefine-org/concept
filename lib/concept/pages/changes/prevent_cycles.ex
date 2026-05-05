defmodule Concept.Pages.Changes.PreventCycles do
  @moduledoc "Reject `:reparent` if the new parent is a descendant of the moving page."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      moving_id = cs.data.id
      new_parent = Ash.Changeset.get_attribute(cs, :parent_page_id)

      cond do
        is_nil(new_parent) ->
          cs

        new_parent == moving_id ->
          Ash.Changeset.add_error(cs, field: :parent_page_id, message: "cannot parent to self")

        descendant?(moving_id, new_parent) ->
          Ash.Changeset.add_error(cs, field: :parent_page_id, message: "would create a cycle")

        true ->
          cs
      end
    end)
  end

  defp descendant?(ancestor_id, candidate_id) do
    {:ok, %{rows: rows}} =
      Concept.Repo.query(
        """
          WITH RECURSIVE descendants AS (
            SELECT id, parent_page_id FROM pages WHERE id = $1
            UNION ALL
            SELECT p.id, p.parent_page_id FROM pages p INNER JOIN descendants d ON d.id = p.parent_page_id
          )
          SELECT 1 FROM descendants WHERE id = $2 LIMIT 1
        """,
        [Ecto.UUID.dump!(ancestor_id), Ecto.UUID.dump!(candidate_id)]
      )

    rows != []
  end
end
