defmodule Concept.Knowledge.Link do
  @moduledoc """
  User-authored block-to-block graph edges. Each Link row mirrors into
  `Arcana.Graph.Relationship` via an after_action change.
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  postgres do
    table "knowledge_links"
    repo Concept.Repo

    references do
      reference :source_block, on_delete: :delete
      reference :target_block, on_delete: :delete
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

  paper_trail do
    primary_key_type :uuid
  end

  attributes do
    uuid_primary_key :id

    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :source_block_id, :uuid, allow_nil?: false, public?: true
    attribute :target_block_id, :uuid, allow_nil?: false, public?: true

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:relates_to, :cites, :contradicts, :see_also]]

    attribute :note, :string, public?: true
    attribute :created_by_user_id, :uuid, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :source_block, Concept.Pages.Block,
      source_attribute: :source_block_id,
      destination_attribute: :id

    belongs_to :target_block, Concept.Pages.Block,
      source_attribute: :target_block_id,
      destination_attribute: :id
  end

  identities do
      identity :unique_triple, [:workspace_id, :source_block_id, :target_block_id, :kind]
    end

  actions do
    defaults [:read]

    create :create do
      accept [:source_block_id, :target_block_id, :kind, :note]
      argument :workspace_id, :uuid, allow_nil?: false

      change set_attribute(:workspace_id, arg(:workspace_id))

      change fn changeset, %{actor: actor} ->
        Ash.Changeset.change_attribute(changeset, :created_by_user_id, actor && actor.id)
      end

      validate compare(:source_block_id, is_not_equal: :target_block_id),
              message: "cannot link a block to itself"

      change Concept.Knowledge.Changes.MirrorToArcanaGraph
    end

    destroy :destroy do
      change Concept.Knowledge.Changes.MirrorToArcanaGraph
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type([:read, :create, :destroy]) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end
end
