defmodule Concept.Knowledge.Chat.Message.Changes.CascadeDeleteBlocks do
  @moduledoc """
  On hard-`destroy` of a Message, delete the blocks it contains
  (`container_type = 'message' AND container_id = <message id>`) and their
  descendants.

  Replaces the referential cascade formerly provided by the
  `blocks.message_id` foreign key (`on_delete: :delete_all`), which the
  Container cutover removed when `container_id` became polymorphic (no FK, same
  as `conversations.host_id`). One recursive CTE so nested message blocks
  (tables, columns) cascade in a single round trip, in the same transaction as
  the message delete.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      message_id = cs.data.id

      Concept.Repo.query!(
        """
          WITH RECURSIVE roots AS (
            SELECT id FROM blocks
             WHERE container_type = 'message' AND container_id = $1
            UNION ALL
            SELECT b.id FROM blocks b INNER JOIN roots r ON b.parent_block_id = r.id
          )
          DELETE FROM blocks WHERE id IN (SELECT id FROM roots)
        """,
        [Ecto.UUID.dump!(message_id)]
      )

      cs
    end)
  end
end
