defmodule Concept.Pages.Block do
  @moduledoc """
  A typed content unit on a Page. Multitenant by `workspace_id`, archival, paper-trailed,
  and lock-managed via AshStateMachine. Type-specific concerns (default content, props
  validation, render) live in `Concept.Pages.BlockType` plug-in modules.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Pages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshArchival.Resource,
      AshStateMachine,
      AshOban
    ],
    notifiers: [Ash.Notifier.PubSub, Concept.Pages.Notifiers.KnowledgeReindex]

  @lock_ttl_seconds 30

  postgres do
    table "blocks"
    repo Concept.Repo

    references do
      reference :parent_block, on_delete: :nilify
      reference :lock_holder, on_delete: :nilify
    end

    custom_indexes do
      # One index over the polymorphic container discriminator + ordering keys.
      # `container_id` carries no DB foreign key (it is polymorphic, like
      # `Conversation.host_id`); referential integrity for the one hard-delete
      # path (Message destroy) is enforced app-side (see Message :destroy).
      index [:workspace_id, :container_type, :container_id, :parent_block_id, :position]
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  state_machine do
    initial_states [:unlocked]
    default_initial_state :unlocked

    transitions do
      transition :acquire_lock, from: :unlocked, to: :locked
      transition :refresh_lock, from: :locked, to: :locked
      transition :release_lock, from: [:locked, :unlocked], to: :unlocked
    end
  end

  oban do
    triggers do
      trigger :release_expired_locks do
        action :release_lock
        where expr(lock_state == :locked and lock_expires_at < now())
        scheduler_cron "*/10 * * * *"
        queue :locks
        use_tenant_from_record? true
        list_tenants Concept.AshOban.WorkspaceTenants
        actor_persister Concept.AshOban.SystemActorPersister
        worker_module_name Concept.Pages.Block.AshOban.Worker.ReleaseExpiredLocks
        scheduler_module_name Concept.Pages.Block.AshOban.Scheduler.ReleaseExpiredLocks
      end
    end
  end

  actions do
    defaults [:read]

    create :create_block do
      description "Create a new block in a container (a page or a message), optionally as a child of another block."

      accept [
        :container_type,
        :container_id,
        :parent_block_id,
        :type,
        :content,
        :props,
        :position
      ]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the block belongs to. Actor must be a member."

      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Pages.Changes.AssertWorkspaceMatchesTenant
      change Concept.Pages.Block.Changes.AssignDefaults
      change Concept.Pages.Block.Changes.AssignAfterLastSibling
    end

    update :update_content do
      description "Update a block's content (lexical state or block-type-specific payload). Writes directly; no separate lock step is required. Refuses only when another editor currently holds an active lock on the block."
      accept [:content]
      require_atomic? false
      change Concept.Pages.Block.Changes.EnsureEditableLock
    end

    update :update_props do
      description "Update a block's props (block-type-specific configuration)."
      accept [:props]
      require_atomic? false
      change Concept.Pages.Block.Changes.ValidatePropsForType
    end

    update :reorder do
      description "Reorder a block within its current parent."
      accept [:position]
    end

    update :reparent do
      description "Move a block under a new parent at a given position."
      accept [:parent_block_id, :position]
    end

    update :archive do
      description "Archive a block (soft-delete; cascades to children)."
      accept []
      require_atomic? false
      change set_attribute(:archived_at, DateTime.utc_now())
      change Concept.Pages.Block.Changes.CascadeArchive
    end

    update :acquire_lock do
      description "Acquire a collaborative-editing lock on the block. Required before mutating content."

      argument :user_id, :uuid,
        allow_nil?: false,
        description: "User acquiring the lock; must match the actor."

      argument :ttl_seconds, :integer,
        default: 30,
        description: "Lock lifetime in seconds before automatic release."

      accept []
      require_atomic? false
      change transition_state(:locked)
      change set_attribute(:lock_state, :locked)
      change Concept.Pages.Block.Changes.SetLockMetadata
    end

    update :refresh_lock do
      description "Refresh an active lock's TTL while the actor continues editing."

      argument :user_id, :uuid,
        allow_nil?: false,
        description: "User holding the lock; must match the actor."

      argument :ttl_seconds, :integer,
        default: 30,
        description: "New lock lifetime in seconds."

      accept []
      require_atomic? false
      change transition_state(:locked)
      change set_attribute(:lock_state, :locked)
      change Concept.Pages.Block.Changes.SetLockMetadata
    end

    update :release_lock do
      description "Release a previously acquired editing lock."
      accept []
      require_atomic? false
      change transition_state(:unlocked)
      change set_attribute(:lock_state, :unlocked)
      change set_attribute(:lock_holder_id, nil)
      change set_attribute(:lock_acquired_at, nil)
      change set_attribute(:lock_expires_at, nil)
    end

    update :evaluate_ai do
      description "Evaluate an AI Answer block against the current page or workspace context."

      argument :prompt, :string,
        allow_nil?: false,
        description: "Question to answer using workspace content as context."

      argument :scope, :atom,
        constraints: [one_of: [:workspace, :page, :subtree]],
        default: :workspace,
        description: "Retrieval scope. One of :workspace, :page, :subtree."

      argument :profile, :atom,
        constraints: [one_of: [:fast, :default, :thorough, :outline, :contradict, :intent]],
        default: :default,
        description: "Knowledge profile. Determines model + retrieval params."

      accept []
      require_atomic? false
      change Concept.Pages.Block.Changes.EvaluateAi
    end

    read :list_for_page do
      description "List all non-archived blocks on a page, in render order."

      argument :page_id, :uuid,
        allow_nil?: false,
        description: "Page whose blocks to list."

      filter expr(
               container_type == :page and container_id == ^arg(:page_id) and is_nil(archived_at)
             )

      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end

    read :list_for_message do
      description "List all non-archived blocks in a message (a conversation turn's rich body), in render order."

      argument :message_id, :uuid,
        allow_nil?: false,
        description: "Message whose blocks to list."

      filter expr(
               container_type == :message and container_id == ^arg(:message_id) and
                 is_nil(archived_at)
             )

      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end

    read :first_for_page do
      description "Read the first (topmost) non-archived block of a page."
      get? true

      argument :page_id, :uuid,
        allow_nil?: false,
        description: "Page whose first block to read."

      filter expr(
               container_type == :page and container_id == ^arg(:page_id) and is_nil(archived_at)
             )

      prepare build(sort: [position: :asc], limit: 1)
    end

    read :list_for_container do
      description "List all non-archived blocks owned by any container, in render order. The container-agnostic primitive behind the page/message facades."

      argument :container_type, Concept.Containable.TypeAttr,
        allow_nil?: false,
        description: "Container kind that owns the blocks (e.g. :page, :message, :record)."

      argument :container_id, :uuid,
        allow_nil?: false,
        description: "Id of the container whose blocks to list."

      filter expr(
               container_type == ^arg(:container_type) and container_id == ^arg(:container_id) and
                 is_nil(archived_at)
             )

      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end
  end

  policies do
    # Read floor (members) + system bypass come from
    # `Concept.Resources.WorkspaceTenanted`. Below are the block-specific
    # write policies.
    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    policy action_type([:update, :destroy]) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    # Topic is keyed on the polymorphic container. For a page block this renders
    # "workspace:<ws>:page:<id>:blocks" — byte-identical to the pre-Container
    # topic, so page-editor subscribers are unchanged; message blocks get their
    # own "workspace:<ws>:message:<id>:blocks" lane for free.
    publish_all :create, [:workspace_id, :container_type, :container_id, "blocks"],
      event: "block_created"

    publish_all :update, [:workspace_id, :container_type, :container_id, "blocks"],
      event: "block_updated"

    publish :archive, [:workspace_id, :container_type, :container_id, "blocks"],
      event: "block_archived"
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    # The polymorphic container: which surface owns this block. `container_type`
    # is registry-validated (Concept.Containable.TypeAttr); `container_id` is an
    # untyped uuid (no DB FK — same idiom as Conversation.host_id). Together
    # they replace the former page_id-XOR-message_id pair: cardinality is now
    # structural (both not-null) rather than a num_nonnulls check constraint.
    attribute :container_type, Concept.Containable.TypeAttr, allow_nil?: false, public?: true
    attribute :container_id, :uuid, allow_nil?: false, public?: true
    attribute :parent_block_id, :uuid, allow_nil?: true, public?: true
    attribute :type, Concept.Pages.BlockTypeAttr, allow_nil?: false, public?: true
    attribute :position, :string, allow_nil?: false, public?: true
    attribute :content, :map, default: %{}, public?: true
    attribute :props, :map, default: %{}, public?: true

    attribute :lock_state, :atom,
      default: :unlocked,
      public?: true,
      constraints: [one_of: [:unlocked, :locked]]

    attribute :lock_holder_id, :uuid, allow_nil?: true, public?: true
    attribute :lock_acquired_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :lock_expires_at, :utc_datetime_usec, allow_nil?: true, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    # No `belongs_to :page` / `:message`: the container is polymorphic
    # (container_type/container_id), resolved through Concept.Containable rather
    # than a typed association. Container-specific block loads live on the
    # container resources (e.g. Page.blocks / Message.blocks via filtered
    # has_many) — see those resources.
    belongs_to :parent_block, __MODULE__,
      attribute_writable?: true,
      source_attribute: :parent_block_id,
      destination_attribute: :id

    has_many :children, __MODULE__, destination_attribute: :parent_block_id

    belongs_to :lock_holder, Concept.Accounts.User,
      attribute_writable?: true,
      source_attribute: :lock_holder_id,
      destination_attribute: :id
  end

  calculations do
    calculate :plain_text, :string, fn records, _ctx ->
      Enum.map(records, &Concept.Lexical.plain_text(&1.content || %{}))
    end
  end

  aggregates do
    count :children_count, :children
  end

  def lock_ttl_seconds, do: @lock_ttl_seconds
end
