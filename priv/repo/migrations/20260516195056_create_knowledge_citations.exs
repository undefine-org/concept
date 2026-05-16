defmodule Concept.Repo.Migrations.CreateKnowledgeCitations do
  @moduledoc """
  Creates the knowledge_citations table for tracking Citation resources.
  Citations connect AshAI Messages to Concept Blocks/Pages for RAG provenance.
  """
  use Ecto.Migration

  def up do
    create table(:knowledge_citations, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :workspace_id, :uuid, null: false
      add :message_id, :uuid, null: false
      add :block_id, :uuid, null: false
      add :page_id, :uuid, null: false
      add :rank, :integer, null: false
      add :score, :float
      add :snippet, :text
      add :breadcrumbs, :text
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    # Foreign key references with cascade delete
    alter table(:knowledge_citations) do
      modify :message_id,
             references(:messages, type: :uuid, on_delete: :delete_all)

      modify :block_id,
             references(:blocks, type: :uuid, on_delete: :delete_all)

      modify :page_id,
             references(:pages, type: :uuid, on_delete: :delete_all)
    end

    # Indexes for efficient queries
    create index(:knowledge_citations, [:workspace_id, :message_id])
    create index(:knowledge_citations, [:workspace_id, :block_id])
  end

  def down do
    drop table(:knowledge_citations)
  end
end
