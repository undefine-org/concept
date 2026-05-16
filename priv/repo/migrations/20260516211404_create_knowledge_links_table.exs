defmodule Concept.Repo.Migrations.CreateKnowledgeLinksTable do
  use Ecto.Migration

  def up do
    create table(:knowledge_links, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workspace_id, :uuid, null: false
      add :source_block_id, references(:blocks, type: :uuid, on_delete: :delete_all), null: false
      add :target_block_id, references(:blocks, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :note, :text
      add :created_by_user_id, :uuid, null: false

      timestamps(type: :utc_datetime_usec, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create unique_index(
             :knowledge_links,
             [:workspace_id, :source_block_id, :target_block_id, :kind],
             name: :knowledge_links_unique_triple_index
           )
  end

  def down do
    drop table(:knowledge_links)
  end
end
