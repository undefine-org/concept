defmodule Concept.Repo.Migrations.CreateKnowledgeTokenLedger do
  use Ecto.Migration

  def change do
    create table(:knowledge_token_ledger, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :workspace_id, :uuid, null: false
      add :day, :date, null: false
      add :prompt_tokens, :bigint, default: 0, null: false
      add :completion_tokens, :bigint, default: 0, null: false
      add :embed_tokens, :bigint, default: 0, null: false
      add :request_count, :bigint, default: 0, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:knowledge_token_ledger, [:workspace_id, :day])

    create unique_index(:knowledge_token_ledger, [:workspace_id, :day],
             name: "knowledge_token_ledger_one_per_workspace_per_day_index"
           )
  end
end
