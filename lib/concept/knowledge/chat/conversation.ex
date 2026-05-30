defmodule Concept.Knowledge.Chat.Conversation do
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

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
      accept [:title, :host_type, :host_id]

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

    read :my_conversations do
      description "List the actor's chat conversations in the workspace, most recent first."
      filter expr(user_id == ^actor(:id))
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
