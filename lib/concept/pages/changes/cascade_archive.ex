defmodule Concept.Pages.Changes.CascadeArchive do
  @moduledoc "On archive of a Page, cascade archived_at to all descendants in one statement."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.after_action(changeset, fn _cs, page ->
      now = page.archived_at || DateTime.utc_now()

      Concept.Repo.query!(
        """
          WITH RECURSIVE descendants AS (
            SELECT id FROM pages WHERE parent_page_id = $1
            UNION ALL
            SELECT p.id FROM pages p INNER JOIN descendants d ON p.parent_page_id = d.id
          )
          UPDATE pages SET archived_at = $2 WHERE id IN (SELECT id FROM descendants) AND archived_at IS NULL
        """,
        [Ecto.UUID.dump!(page.id), now]
      )

      {:ok, page}
    end)
  end
end
