defmodule Concept.Knowledge.Chat.Message do
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  # A Message owns a tree of Blocks (its rich body); it is a block container,
  # the content-layer twin of being a conversation host. See Concept.Containable.
  use Concept.Containable, type: :message

  oban do
    triggers do
      trigger :respond do
        actor_persister Concept.AiAgentActorPersister
        action :respond
        queue :chat_responses
        lock_for_update? false
        scheduler_cron false
        worker_module_name Concept.Knowledge.Chat.Message.Workers.Respond
        scheduler_module_name Concept.Knowledge.Chat.Message.Schedulers.Respond
        where expr(needs_host_response)
      end
    end
  end

  postgres do
    table "messages"
    repo Concept.Repo
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
      # Replaces the dropped blocks.message_id FK cascade: a message's blocks
      # (container_type = :message) are polymorphic now, so the cascade is
      # enforced here. See Concept.Containable / the Container cutover migration.
      change Concept.Knowledge.Chat.Message.Changes.CascadeDeleteBlocks
    end

    read :for_conversation do
      description "List messages in a chat conversation, most recent first by default."
      pagination keyset?: true, required?: false

      argument :conversation_id, :uuid,
        allow_nil?: false,
        description: "Conversation whose messages to load."

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    create :create do
      description "Send a message to a host (a page, a record, or the workspace). If no conversation exists for that host yet, one is created; the host's grounded AI voice may reply asynchronously."
      accept [:text, :scope, :scope_target_id, :profile, :mentions, :addresses_host]

      validate match(:text, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        public? false
      end

      # Host addressing — the polymorphic, registry-validated subject of the
      # conversation. When `conversation_id` is omitted, the message routes to
      # (or creates) the host's conversation. This is what makes EVERY
      # registered host conversable through ONE action (see Concept.Hostable):
      # no per-host `discuss` action, no parallel wiring.
      argument :host_type, :atom do
        public? true
        default :workspace
        constraints one_of: Concept.Hostable.types()

        description "What this message is about: :workspace (whole tenant) or a registered host type such as :page."
      end

      argument :host_id, :uuid do
        public? true
        allow_nil? true
        description "The host record id (e.g. the page id). Omit for the :workspace host."
      end

      argument :reply_to_message_id, :uuid do
        public? true
        allow_nil? true

        description "Spawn (or continue) a thread: a child conversation seeded from this message, inheriting the parent's host. Omit to post in the conversation directly."
      end

      # The block type the message body becomes (PLAN-010 §27): a message's text
      # is mirrored into a Block of this type under the message, so the body is
      # the same content unit as a page. Defaults to :paragraph.
      argument :block_type, :atom do
        public? true
        default :paragraph
        constraints one_of: [:paragraph, :heading_1, :heading_2, :heading_3, :bulleted_list_item, :numbered_list_item, :to_do, :quote]

        description "The block type the message body becomes (paragraph, heading_1–3, bulleted_list_item, numbered_list_item, to_do, quote). The text is mirrored into a Block of this type so talk carries the editor's content unit and crystallizes by cloning."
      end

      change Concept.Knowledge.Chat.Message.Changes.CreateConversationIfNotProvided
      change Concept.Knowledge.Chat.Message.Changes.MirrorTextToBlock
      change Concept.Knowledge.Chat.Message.Changes.JoinSenderAsParticipant
      change Concept.Knowledge.Chat.Message.Changes.BroadcastInbox
      change run_oban_trigger(:respond)
    end

    update :respond do
      accept []
      require_atomic? false
      transaction? false
      change Concept.Knowledge.Chat.Message.Changes.Respond
    end

    create :upsert_response do
      upsert? true
      accept [:id, :response_to_id, :conversation_id]
      argument :complete, :boolean, default: false
      argument :text, :string, allow_nil?: false, constraints: [trim?: false, allow_empty?: true]
      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      # if updating
      #   if complete, set the text to the provided text
      #   if streaming still, add the text to the provided text
      change atomic_update(
               :text,
               {:atomic,
                expr(
                  if ^arg(:complete) do
                    ^arg(:text)
                  else
                    text <> ^arg(:text)
                  end
                )}
             )

      change atomic_update(
               :tool_calls,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_calls)) do
                    fragment(
                      "? || ?",
                      tool_calls,
                      type(
                        ^arg(:tool_calls),
                        {:array, :map}
                      )
                    )
                  else
                    tool_calls
                  end
                )}
             )

      change atomic_update(
               :tool_results,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_results)) do
                    fragment(
                      "? || ?",
                      tool_results,
                      type(
                        ^arg(:tool_results),
                        {:array, :map}
                      )
                    )
                  else
                    tool_results
                  end
                )}
             )

      # if creating, set the text attribute to the provided text
      change set_attribute(:text, arg(:text))
      change set_attribute(:complete, arg(:complete))
      change set_attribute(:source, :agent)
      change set_attribute(:tool_results, arg(:tool_results))
      change set_attribute(:tool_calls, arg(:tool_calls))

      # on update, only set complete to its new value
      # `:complete` is set via the action's `set_attribute` change. Audit
      # columns (`prompt_tokens`, `completion_tokens`, `latency_ms`,
      # `grounding_score`, `search_trace`, `rewritten_prompt`) are
      # force-changed by `Concept.Knowledge.Chat.Message.Changes.Respond` on
      # finalize; listing them here propagates their values through the
      # `ON CONFLICT DO UPDATE` clause so they overwrite the partial row
      # that was upserted during streaming.
      upsert_fields [
        :complete,
        :prompt_tokens,
        :completion_tokens,
        :latency_ms,
        :grounding_score,
        :search_trace,
        :rewritten_prompt
      ]
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "chat"

    publish :create, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          text: message.text,
          id: message.id,
          source: message.source,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end

    publish :upsert_response, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          text: message.text,
          id: message.id,
          source: message.source,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

  attributes do
    timestamps()
    uuid_v7_primary_key :id, writable?: true

    attribute :text, :string do
      constraints allow_empty?: true, trim?: false
      public? true
      allow_nil? false
    end

    attribute :tool_calls, {:array, :map}
    attribute :tool_results, {:array, :map}

    attribute :source, Concept.Knowledge.Chat.Message.Types.Source do
      allow_nil? false
      public? true
      default :user
    end

    attribute :complete, :boolean do
      allow_nil? false
      default true
    end

    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    attribute :scope, :atom do
      constraints one_of: [:workspace, :page, :subtree]
      default :workspace
      public? true
      allow_nil? false
    end

    attribute :scope_target_id, :uuid do
      public? true
      allow_nil? true
    end

    attribute :profile, :atom do
      constraints one_of: [:fast, :default, :thorough, :outline, :contradict, :intent]
      default :default
      public? true
      allow_nil? false
    end

    attribute :rewritten_prompt, :string do
      public? false
      allow_nil? true
    end

    attribute :search_trace, {:array, :map} do
      public? false
      allow_nil? false
      default []
    end

    attribute :prompt_tokens, :integer do
      public? false
      allow_nil? true
    end

    attribute :completion_tokens, :integer do
      public? false
      allow_nil? true
    end

    attribute :latency_ms, :integer do
      public? false
      allow_nil? true
    end

    attribute :grounding_score, :float do
      public? false
      allow_nil? true
    end

    # The sender's identity, when a participant (human or agent) spoke.
    # NULL means the HOST spoke (its voice has no identity of its own; see
    # Participant moduledoc and docs/messaging_design.md §37). The legacy
    # `:source` attribute is retained as a transitional shim until the cutover
    # completes; `sender_kind` (calc) is the forward-looking read.
    attribute :sender_participant_id, :uuid do
      public? true
      allow_nil? true

      description "The participant (member) who sent this message. Null when the host's grounded voice spoke."
    end

    # Addressed participants/hosts. A mention of a member notifies (inbox); a
    # mention of the host voice enqueues a grounded response (see needs_host_response).
    attribute :mentions, {:array, :uuid} do
      public? true
      allow_nil? false
      default []
      description "Participant ids addressed by this message (@-mentions)."
    end

    # Whether this message addresses the host's grounded voice (i.e. wants an
    # AI reply). This is what KILLS the old "every user message summons the AI"
    # reflex (docs/messaging_design.md §4, §B.2): human↔human messages set this
    # false and no response is owed. Defaults true to preserve today's
    # workspace-chat behaviour during the cutover.
    attribute :addresses_host, :boolean do
      public? true
      allow_nil? false
      default true

      description "True if this message addresses the host's AI voice (an asynchronous grounded reply is owed). Set false for human-to-human messages."
    end
  end

  relationships do
    belongs_to :conversation, Concept.Knowledge.Chat.Conversation do
      public? true
      allow_nil? false
    end

    belongs_to :response_to, __MODULE__ do
      public? true
    end

    has_one :response, __MODULE__ do
      public? true
      destination_attribute :response_to_id
    end

    belongs_to :sender_participant, Concept.Knowledge.Chat.Participant do
      public? true
      define_attribute? false
      source_attribute :sender_participant_id
      destination_attribute :id
    end

    # A message's rich body: Blocks (the same content unit as a page). Talk
    # carries the editor's full expressiveness; crystallization reparents these
    # onto the host page (PLAN-010 §27). `text` is retained as a plain-text
    # fast-path shim alongside this.
    has_many :blocks, Concept.Pages.Block do
      destination_attribute :container_id
      filter expr(container_type == :message)
    end
  end

  calculations do
    # A host response is owed iff: a member (not the host) sent the message,
    # the host's voice is addressed, and no reply exists yet. Generalizes the
    # old `needs_response` (which fired on EVERY user message — the reflex).
    # The agent-turn budget conjunct lands in Wave 4 (FEAT-078).
    calculate :needs_host_response, :boolean do
      calculation expr(
                    source == :user and addresses_host and not exists(response) and
                      conversation.agent_turn_budget > 0
                  )
    end
  end

  @doc """
  Describe a message as a knowledge-ingest source: its rich blocks become
  searchable conversation content. `:skip` for a text-only message (no blocks).
  A message has no title, so the body is a stable breadcrumb. See
  `Concept.Containable.ingest_descriptor/2`.
  """
  @impl Concept.Containable
  def ingest_descriptor(message_id, workspace_id) do
    actor = %{system?: true}

    case Concept.Pages.list_for_message(message_id, actor: actor, tenant: workspace_id) do
      {:ok, []} ->
        :skip

      {:ok, blocks} ->
        {:ok,
         %{
           source_id: "message:#{message_id}",
           body: "Message",
           chunker_opts: [
             blocks: blocks,
             workspace_id: workspace_id,
             message_id: message_id,
             breadcrumbs: "Conversation"
           ]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
