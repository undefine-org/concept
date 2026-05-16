defmodule Concept.Knowledge.Citation do
  @moduledoc """
  Connective tissue between an AshAI Message and a Concept Block.
  Records ranked retrieval results during RAG queries, enabling
  citation trails and reverse lookups.
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "knowledge_citations"
    repo Concept.Repo

    references do
      reference :block, on_delete: :delete
      reference :page, on_delete: :delete
      reference :message, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :message_id]
      index [:workspace_id, :block_id]
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
    attribute :message_id, :uuid, allow_nil?: false, public?: true
    attribute :block_id, :uuid, allow_nil?: false, public?: true
    attribute :page_id, :uuid, allow_nil?: false, public?: true
    attribute :rank, :integer, allow_nil?: false, public?: true
    attribute :score, :float, constraints: [min: 0.0, max: 1.0], public?: true
    attribute :snippet, :string, public?: true
    attribute :breadcrumbs, :string, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :message, Concept.Knowledge.Chat.Message,
      source_attribute: :message_id,
      destination_attribute: :id

    belongs_to :block, Concept.Pages.Block,
      source_attribute: :block_id,
      destination_attribute: :id

    belongs_to :page, Concept.Pages.Page,
      source_attribute: :page_id,
      destination_attribute: :id
  end

  actions do
    defaults [:read]

    create :create do
      accept [:message_id, :block_id, :page_id, :rank, :score, :snippet, :breadcrumbs]
      argument :workspace_id, :uuid, allow_nil?: false
      change set_attribute(:workspace_id, arg(:workspace_id))
    end

    read :for_message do
      argument :message_id, :uuid, allow_nil?: false
      filter expr(message_id == ^arg(:message_id))
      prepare build(sort: [rank: :asc])
    end

    read :for_block do
      argument :block_id, :uuid, allow_nil?: false
      filter expr(block_id == ^arg(:block_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:system?, true)
    end
  end
end
