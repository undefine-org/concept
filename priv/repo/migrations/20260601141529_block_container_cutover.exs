defmodule Concept.Repo.Migrations.BlockContainerCutover do
  @moduledoc """
  Cut `blocks` over from the `page_id` XOR `message_id` pair to a polymorphic
  `container_type` / `container_id` discriminator (the Concept.Containable
  model). Data-preserving and reversible.

  up:
    1. add nullable container_type / container_id
    2. backfill from page_id / message_id
    3. drop the old indexes, check constraint, and FK columns
    4. make container_* NOT NULL + add the unified index

  down: the exact inverse (re-add page_id/message_id, backfill, restore the
  XOR check + per-container indexes + FKs, drop container_*).

  `container_id` intentionally carries NO foreign key — it is polymorphic, like
  `conversations.host_id`. The single referential edge this removes
  (message delete -> its blocks, formerly `on_delete: :delete_all`) is replaced
  app-side on the Message `:destroy` path.
  """
  use Ecto.Migration

  def up do
    alter table(:blocks) do
      add :container_type, :text
      add :container_id, :uuid
    end

    # Backfill: every existing block had exactly one of page_id / message_id.
    execute """
    UPDATE blocks
       SET container_type = 'page', container_id = page_id
     WHERE page_id IS NOT NULL
    """

    execute """
    UPDATE blocks
       SET container_type = 'message', container_id = message_id
     WHERE message_id IS NOT NULL
    """

    # Retire the old container columns, their indexes, the XOR check, and FKs.
    drop_if_exists constraint(:blocks, :blocks_one_container)
    drop_if_exists index(:blocks, [:workspace_id, :page_id, :parent_block_id, :position])
    drop_if_exists index(:blocks, [:workspace_id, :message_id, :position])

    drop_if_exists constraint(:blocks, "blocks_message_id_fkey")
    drop_if_exists constraint(:blocks, "blocks_page_id_fkey")

    alter table(:blocks) do
      remove :page_id
      remove :message_id
    end

    # Cardinality is now structural: a block always has a container.
    execute "ALTER TABLE blocks ALTER COLUMN container_type SET NOT NULL"
    execute "ALTER TABLE blocks ALTER COLUMN container_id SET NOT NULL"

    create index(:blocks, [
             :workspace_id,
             :container_type,
             :container_id,
             :parent_block_id,
             :position
           ])
  end

  def down do
    alter table(:blocks) do
      add :page_id,
          references(:pages,
            column: :id,
            name: "blocks_page_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )

      add :message_id,
          references(:messages,
            column: :id,
            name: "blocks_message_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    execute """
    UPDATE blocks
       SET page_id = container_id
     WHERE container_type = 'page'
    """

    execute """
    UPDATE blocks
       SET message_id = container_id
     WHERE container_type = 'message'
    """

    drop_if_exists index(:blocks, [
                     :workspace_id,
                     :container_type,
                     :container_id,
                     :parent_block_id,
                     :position
                   ])

    alter table(:blocks) do
      remove :container_type
      remove :container_id
    end

    create index(:blocks, [:workspace_id, :page_id, :parent_block_id, :position])
    create index(:blocks, [:workspace_id, :message_id, :position])

    create constraint(:blocks, :blocks_one_container,
             check: """
               num_nonnulls(page_id, message_id) = 1
             """
           )
  end
end
