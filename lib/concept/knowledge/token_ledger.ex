defmodule Concept.Knowledge.TokenLedger do
  @moduledoc """
  Daily aggregated Gemini token usage per workspace. Tracks prompt, completion,
  and embedding tokens consumed through knowledge ingestion and answer pipelines.
  Populated by `Concept.Knowledge.Workers.AggregateTokens` from telemetry accumulator.
  """
  use Ash.Resource,
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

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

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

  actions do
    defaults [:read]

    create :upsert do
      accept [:workspace_id, :day, :prompt_tokens, :completion_tokens, :embed_tokens, :request_count]
      upsert? true
      upsert_identity :one_per_workspace_per_day
      upsert_fields [:prompt_tokens, :completion_tokens, :embed_tokens, :request_count]
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end
end
