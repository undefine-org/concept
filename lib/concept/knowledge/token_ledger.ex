defmodule Concept.Knowledge.TokenLedger do
  @moduledoc """
  Daily aggregated Gemini token usage per workspace. Tracks prompt, completion,
  and embedding tokens consumed through knowledge ingestion and answer pipelines.
  Populated by `Concept.Knowledge.Workers.AggregateTokens` from telemetry accumulator.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "knowledge_token_ledger"
    repo Concept.Repo

    custom_indexes do
      index [:workspace_id, :day]
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [
        :workspace_id,
        :day,
        :prompt_tokens,
        :completion_tokens,
        :embed_tokens,
        :request_count
      ]

      upsert? true
      upsert_identity :one_per_workspace_per_day
      upsert_fields [:prompt_tokens, :completion_tokens, :embed_tokens, :request_count]
    end
  end

  # Read floor (members) + system bypass come from
  # `Concept.Resources.WorkspaceTenanted`. Writes are system-only via that
  # bypass; no additional policies needed.

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :day, :date, allow_nil?: false, public?: true
    attribute :prompt_tokens, :integer, default: 0, public?: true
    attribute :completion_tokens, :integer, default: 0, public?: true
    attribute :embed_tokens, :integer, default: 0, public?: true
    attribute :request_count, :integer, default: 0, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_per_workspace_per_day, [:workspace_id, :day]
  end
end
