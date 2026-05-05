defmodule Concept.Pages.Block do
  @moduledoc """
  A typed content unit on a Page. Multitenant by `workspace_id`, archival, paper-trailed,
  and lock-managed via AshStateMachine. Type-specific concerns (default content, props
  validation, render) live in `Concept.Pages.BlockType` plug-in modules.
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Pages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshArchival.Resource,
      AshStateMachine
    ],
    notifiers: [Ash.Notifier.PubSub]

  @lock_ttl_seconds 30

  postgres do
    table "blocks"
    repo Concept.Repo

    references do
      reference :page, on_delete: :delete
      reference :parent_block, on_delete: :nilify
      reference :lock_holder, on_delete: :nilify
    end

    custom_indexes do
      index [:workspace_id, :page_id, :parent_block_id, :position]
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
      transition :release_lock, from: :locked, to: :unlocked
    end
  end

  actions do
    defaults [:read]

    create :create_block do
      accept [:page_id, :parent_block_id, :type, :content, :props]
      argument :workspace_id, :uuid, allow_nil?: false
      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Pages.Block.Changes.AssignDefaults
      change Concept.Pages.Block.Changes.AssignAfterLastSibling
    end

    update :update_content do
      accept [:content]
      change Concept.Pages.Block.Changes.RequireOwnLock
    end

    update :update_props do
      accept [:props]
      change Concept.Pages.Block.Changes.ValidatePropsForType
    end

    update :reorder do
      accept [:position]
    end

    update :reparent do
      accept [:parent_block_id, :position]
    end

    update :archive do
      accept []
    end

    update :acquire_lock do
      argument :user_id, :uuid, allow_nil?: false
      argument :ttl_seconds, :integer, default: 30
      accept []
      change transition_state(:locked)
      change Concept.Pages.Block.Changes.SetLockMetadata
    end

    update :refresh_lock do
      argument :user_id, :uuid, allow_nil?: false
      argument :ttl_seconds, :integer, default: 30
      accept []
      change transition_state(:locked)
      change Concept.Pages.Block.Changes.SetLockMetadata
    end

    update :release_lock do
      accept []
      change transition_state(:unlocked)
      change set_attribute(:lock_holder_id, nil)
      change set_attribute(:lock_acquired_at, nil)
      change set_attribute(:lock_expires_at, nil)
    end

    read :list_for_page do
      argument :page_id, :uuid, allow_nil?: false
      filter expr(page_id == ^arg(:page_id))
      prepare build(sort: [parent_block_id: :asc, position: :asc])
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy always() do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    publish_all :create, ["*", :workspace_id, "page", :page_id, "blocks"], event: "block_created"
    publish_all :update, ["*", :workspace_id, "page", :page_id, "blocks"], event: "block_updated"
    publish :archive, ["*", :workspace_id, "page", :page_id, "blocks"], event: "block_archived"
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :page_id, :uuid, allow_nil?: false, public?: true
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
      source_attribute: :page_id,
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
