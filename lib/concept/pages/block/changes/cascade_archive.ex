defmodule Concept.Pages.Block.Changes.CascadeArchive do
  @moduledoc """
  On archive of a Block, recursively archive every descendant block
  (children via `parent_block_id`). Single SQL statement via CTE so
  composite parents (Table → TableCells, Columns → Columns) and any
  future nested composites cascade in one round trip.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.after_action(changeset, fn _cs, block ->
      now = block.archived_at || DateTime.utc_now()

      Concept.Repo.query!(
        """
          WITH RECURSIVE descendants AS (
            SELECT id FROM blocks WHERE parent_block_id = $1
            UNION ALL
            SELECT b.id FROM blocks b INNER JOIN descendants d ON b.parent_block_id = d.id
          )
          UPDATE blocks SET archived_at = $2 WHERE id IN (SELECT id FROM descendants) AND archived_at IS NULL
        """,
        [Ecto.UUID.dump!(block.id), now]
      )

      {:ok, block}
    end)
  end
end
