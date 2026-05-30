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
      reference :page, on_delete: :delete
      reference :parent_block, on_delete: :nilify
      reference :lock_holder, on_delete: :nilify
      reference :message, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :page_id, :parent_block_id, :position]
      index [:workspace_id, :message_id, :position]
    end

    check_constraints do
      check_constraint :page_id,
        name: "blocks_one_container",
        check: "num_nonnulls(page_id, message_id) = 1",
        message: "a block must belong to exactly one of a page or a message"
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
      description "Create a new block on a page, optionally as a child of another block."
      accept [:page_id, :message_id, :parent_block_id, :type, :content, :props, :position]

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

      filter expr(page_id == ^arg(:page_id) and is_nil(archived_at))
      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end

    read :list_for_message do
      description "List all non-archived blocks in a message (a conversation turn's rich body), in render order."

      argument :message_id, :uuid,
        allow_nil?: false,
        description: "Message whose blocks to list."

      filter expr(message_id == ^arg(:message_id) and is_nil(archived_at))
      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end

    read :first_for_page do
      description "Read the first (topmost) non-archived block of a page."
      get? true

      argument :page_id, :uuid,
        allow_nil?: false,
        description: "Page whose first block to read."

      filter expr(page_id == ^arg(:page_id) and is_nil(archived_at))
      prepare build(sort: [position: :asc], limit: 1)
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

    publish_all :create, [:workspace_id, "page", :page_id, "blocks"], event: "block_created"
    publish_all :update, [:workspace_id, "page", :page_id, "blocks"], event: "block_updated"
    publish :archive, [:workspace_id, "page", :page_id, "blocks"], event: "block_archived"
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    # page_id XOR message_id (enforced by the :one_container check constraint).
    attribute :page_id, :uuid, allow_nil?: true, public?: true, writable?: true
    attribute :message_id, :uuid, allow_nil?: true, public?: true, writable?: true
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
    belongs_to :page, Concept.Pages.Page,
      attribute_writable?: true,
      define_attribute?: false,
      source_attribute: :page_id,
      destination_attribute: :id

    belongs_to :message, Concept.Knowledge.Chat.Message,
      attribute_writable?: true,
      define_attribute?: false,
      source_attribute: :message_id,
      destination_attribute: :id

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
