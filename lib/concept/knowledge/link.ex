defmodule Concept.Knowledge.Link do
  @moduledoc """
  User-authored block-to-block graph edges. Each Link row mirrors into
  `Arcana.Graph.Relationship` via an after_action change.
  """
  use Concept.Resources.WorkspaceTenanted,
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

  paper_trail do
    primary_key_type(:uuid)
    ignore_attributes([:inserted_at, :updated_at])
    attributes_as_attributes([:workspace_id])
    create_version_on_destroy?(false)
  end

  actions do
    defaults [:read]

    create :create do
      description "Assert a typed relationship between two blocks (e.g. supports, contradicts, depends_on)."

      accept [:source_block_id, :target_block_id, :kind, :note]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace both blocks belong to."

      change set_attribute(:workspace_id, arg(:workspace_id))

      change fn changeset, %{actor: actor} ->
        user_id =
          if actor && Map.has_key?(actor, :id),
            do: actor.id,
            else: "00000000-0000-0000-0000-000000000000"

        Ash.Changeset.change_attribute(changeset, :created_by_user_id, user_id)
      end

      validate compare(:source_block_id, is_not_equal: :target_block_id),
        message: "cannot link a block to itself"

      # AshAI builds its tool registry by calling `Ash.can?` on every action
      # with an *empty* input; that invocation reaches this validation with all
      # three attrs `nil`. Short-circuit before touching the DB so the
      # permission probe doesn't crash on `Concept.Repo.get(..., nil)`. The
      # missing-id case is already covered by attribute-level required checks,
      # so this cross-row validation has nothing meaningful to add when ids
      # are absent. See `test/concept/knowledge/link_test.exs` regression test.
      validate fn changeset, _ctx ->
        workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)
        source_block_id = Ash.Changeset.get_attribute(changeset, :source_block_id)
        target_block_id = Ash.Changeset.get_attribute(changeset, :target_block_id)

        if is_nil(source_block_id) or is_nil(target_block_id) or is_nil(workspace_id) do
          :ok
        else
          source = Concept.Repo.get(Concept.Pages.Block, source_block_id)
          target = Concept.Repo.get(Concept.Pages.Block, target_block_id)

          cond do
            is_nil(source) ->
              {:error, field: :source_block_id, message: "does not exist"}

            is_nil(target) ->
              {:error, field: :target_block_id, message: "does not exist"}

            source.workspace_id != workspace_id ->
              {:error, field: :source_block_id, message: "belongs to a different workspace"}

            target.workspace_id != workspace_id ->
              {:error, field: :target_block_id, message: "belongs to a different workspace"}

            true ->
              :ok
          end
        end
      end

      change Concept.Knowledge.Changes.MirrorToArcanaGraph
    end

    destroy :destroy do
      description "Remove a previously asserted relationship between two blocks."
      require_atomic? false
      change Concept.Knowledge.Changes.MirrorToArcanaGraph
    end
  end

  policies do
    # Read floor (members) + system bypass come from
    # `Concept.Resources.WorkspaceTenanted`. Below are the link-specific
    # write policies.
    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    policy action_type(:destroy) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
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
end
