defmodule Concept.Repo.Migrations.AddLinkVersions do
  use Ecto.Migration

  def up do
    create table(:knowledge_links_versions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :version_action_type, :text, null: false
      add :workspace_id, :uuid, null: false

      add :version_source_id, references(:knowledge_links, type: :uuid, on_delete: :delete_all),
        null: false

      add :changes, :map

      add :version_inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :version_updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end
  end

  def down do
    drop table(:knowledge_links_versions)
  end
end
