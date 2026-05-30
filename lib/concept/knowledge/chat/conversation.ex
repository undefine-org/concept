defmodule Concept.Knowledge.Chat.Conversation do
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  # Default automatic agent/host turns before a human must re-engage (PLAN-010 §B).
  @default_budget 5

  oban do
    triggers do
      trigger :name_conversation do
        action :generate_name
        queue :conversations
        lock_for_update? false
        # global? false multitenancy: the cron scheduler must enumerate tenants
        # and run the worker under each record's tenant (BUG-043 pattern).
        use_tenant_from_record? true
        list_tenants Concept.AshOban.WorkspaceTenants
        actor_persister Concept.AshOban.SystemActorPersister
        worker_module_name Concept.Knowledge.Chat.Message.Workers.NameConversation
        scheduler_module_name Concept.Knowledge.Chat.Message.Schedulers.NameConversation
        where expr(needs_title)
      end
    end
  end

  postgres do
    table "conversations"
    repo Concept.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Start a new chat conversation in the workspace."
      accept [:title, :host_type, :host_id, :parent_conversation_id, :seed_message_id]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the conversation belongs to."

      change set_attribute(:workspace_id, arg(:workspace_id))
      # Transitional: the creator is still related as `user` until the
      # Participant model lands (Wave 1, FEAT-076). Host defaults to
      # :workspace (the degenerate, workspace-wide conversation).
      change relate_actor(:user)
    end

    update :generate_name do
      accept []
      transaction? false
      require_atomic? false
      change Concept.Knowledge.Chat.Conversation.Changes.GenerateName
    end

    update :decrement_budget do
      description "Atomically consume one automatic agent/host turn from the budget (floored at 0)."
      accept []

      change atomic_update(
               :agent_turn_budget,
               expr(fragment("GREATEST(? - 1, 0)", agent_turn_budget))
             )
    end

    update :replenish_budget do
      description "Reset the agent-turn budget when a human re-engages the conversation."
      accept []
      change set_attribute(:agent_turn_budget, @default_budget)
    end

    update :mark_crystallized do
      description "Record that this conversation was crystallized into a durable page."
      accept [:crystallized_page_id]
    end

    action :crystallize, {:array, :uuid} do
      description "Crystallize this conversation into a durable page: clone its message blocks onto the page with provenance links, then mark it crystallized."

      argument :conversation_id, :uuid,
        allow_nil?: false,
        description: "The conversation to crystallize."

      argument :target_page_id, :uuid,
        allow_nil?: false,
        description: "The page to crystallize the conversation into."

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace tenant."

      run Concept.Knowledge.Chat.Reactors.Crystallize
    end

    read :my_conversations do
      description "List the actor's chat conversations in the workspace, most recent first."
      filter expr(user_id == ^actor(:id))
    end

    read :inbox do
      description "List conversations the current actor participates in, most recently active first (the inbox projection)."
      filter expr(exists(participants, membership.user_id == ^actor(:id)))
      prepare build(sort: [updated_at: :desc])
    end

    read :for_seed do
      description "Find the thread (child conversation) spawned from a given seed message, if any."

      argument :seed_message_id, :uuid,
        allow_nil?: false,
        description: "The message a thread was spawned from."

      filter expr(seed_message_id == ^arg(:seed_message_id))
    end

    read :for_host do
      description "List conversations about a given host (e.g. a page), most recent first."

      argument :host_type, :atom,
        allow_nil?: false,
        constraints: [one_of: Concept.Hostable.types()],
        description: "The host type, e.g. :page or :workspace."

      argument :host_id, :uuid,
        allow_nil?: true,
        description: "The host record id; nil for the :workspace host."

      filter expr(host_type == ^arg(:host_type) and host_id == ^arg(:host_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    # Read: a participant of the conversation, OR (today's binary workspace ACL)
    # any workspace member. The participant clause enables private conversations
    # later without foreclosing today's member-sees-all.
    policy action_type(:read) do
      authorize_if expr(exists(participants, membership.user_id == ^actor(:id)))
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end

    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    policy action_type([:update, :destroy]) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end

    # Generic actions (e.g. :crystallize) — workspace members may invoke.
    # WorkspaceMember is a FilterCheck (unusable with generic actions), so use
    # the SimpleCheck WorkspaceMemberCreate.
    policy action_type(:action) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "chat"

    publish_all :create, ["conversations", :user_id] do
      transform & &1.data
    end

    publish_all :update, ["conversations", :user_id] do
      transform & &1.data
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    attribute :host_type, :atom do
      public? true
      allow_nil? false
      default :workspace
      constraints one_of: Concept.Hostable.types()

      description "What this conversation is about: :workspace (whole tenant) or a registered host type (e.g. :page)."
    end

    attribute :host_id, :uuid do
      public? true
      allow_nil? true

      description "The host record id. Nil for the :workspace host (the conversation is about the whole workspace)."
    end

    # Threads: a thread is a child conversation spawned from a message. It
    # inherits the parent's host and links back via these pointers (PLAN-010
    # §13). nil for a root conversation.
    attribute :parent_conversation_id, :uuid do
      public? true
      allow_nil? true

      description "Parent conversation, if this is a thread spawned from a message. Nil for a root conversation."
    end

    attribute :seed_message_id, :uuid do
      public? true
      allow_nil? true
      description "The message this thread was spawned from. Nil for a root conversation."
    end

    # Bounds agent turns to prevent runaway agent↔agent loops AND delegation
    # depth (PLAN-010 §B, §22). Each host/agent turn decrements it; a human
    # message replenishes it (human attention is the rate-limiter). When 0, the
    # needs_host_response calc goes false and the respond trigger stops firing.
    # Set when the conversation has been crystallized into a durable page
    # (PLAN-010 §20, §46): talk became document. Nil while still live.
    attribute :crystallized_page_id, :uuid do
      public? true
      allow_nil? true
      description "The page this conversation was crystallized into, if any."
    end

    attribute :agent_turn_budget, :integer do
      public? true
      allow_nil? false
      default 5

      description "Remaining automatic agent/host turns before a human must re-engage. Replenished when a human posts."
    end

    timestamps()
  end

  relationships do
    has_many :messages, Concept.Knowledge.Chat.Message do
      public? true
    end

    has_many :participants, Concept.Knowledge.Chat.Participant do
      destination_attribute :conversation_id
    end

    # Drives Concept.Pages.Checks.WorkspaceMember (a FilterCheck): the EXISTS
    # subquery fuses into the action SQL. Conversation uses plain Ash.Resource
    # (not WorkspaceTenanted), so this relationship is declared explicitly
    # (mirrors what WorkspaceTenanted injects).
    has_many :workspace_memberships, Concept.Accounts.Membership do
      no_attributes? true
      filter expr(workspace_id == parent(workspace_id))
    end

    belongs_to :user, Concept.Accounts.User do
      public? true
      allow_nil? false
    end

    belongs_to :parent_conversation, __MODULE__ do
      public? true
      define_attribute? false
      source_attribute :parent_conversation_id
      destination_attribute :id
    end

    has_many :threads, __MODULE__ do
      destination_attribute :parent_conversation_id
    end
  end

  calculations do
    calculate :needs_title, :boolean do
      calculation expr(
                    is_nil(title) and
                      (count(messages) > 3 or
                         (count(messages) > 1 and inserted_at < ago(10, :minute)))
                  )
    end
  end
end
