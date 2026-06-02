defmodule Concept.Knowledge.Chat.Participant do
  @moduledoc """
  A speaker in a conversation: the join of a `Membership` (a human or an
  external agent — the two *identities*) into a `Conversation`.

  ## Identity vs. voice (the Wave 1 keystone — see docs/messaging_design.md §36-42)

  A Participant is an **identity**: a principal (Membership) that authorizes
  actions and carries per-conversation state (the unread cursor that *is* the
  inbox). The two identity kinds are derived from `membership.role`:

    * `:user`  — a human member (role `:owner` / `:admin` / `:member`)
    * `:agent` — an external agent member (role `:agent`, authenticating over
      `/mcp` with a workspace-bound API key)

  The third "speaker", the **host**, is deliberately NOT a Participant: it has a
  *voice* (persona + grounding subgraph) but no identity of its own. A host turn
  authorizes as the participant who addressed it (a leak-safe deputy). On a
  `Message`, a null `sender_participant_id` means "the host spoke".

  So `kind` here is only ever `:user` or `:agent`, and it is **derived** from
  `membership.role`, never stored — one source of truth.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Knowledge.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chat_participants"
    repo Concept.Repo

    references do
      reference :conversation, on_delete: :delete
      reference :membership, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :conversation_id]
      index [:workspace_id, :membership_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :join do
      description "Add a member (human or agent) as a participant in a conversation."
      upsert? true
      upsert_identity :unique_membership_per_conversation

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the participant belongs to."

      argument :conversation_id, :uuid,
        allow_nil?: false,
        description: "Conversation the member is joining."

      argument :membership_id, :uuid,
        allow_nil?: false,
        description: "Membership (identity) of the joining human or agent."

      change set_attribute(:workspace_id, arg(:workspace_id))
      change set_attribute(:conversation_id, arg(:conversation_id))
      change set_attribute(:membership_id, arg(:membership_id))
    end

    update :mark_read do
      description "Advance this participant's unread cursor to a message they've now seen."
      accept [:last_read_message_id]
    end

    read :for_conversation do
      description "List the participants (members) of a conversation."

      argument :conversation_id, :uuid,
        allow_nil?: false,
        description: "Conversation whose participants to load."

      filter expr(conversation_id == ^arg(:conversation_id))
    end

    read :my_unread do
      description "List the actor's participant rows with unread messages — the conversation has a latest message the participant's cursor has not reached. One row per unread conversation; count them for an unread badge."

      filter expr(
               membership.user_id == ^actor(:id) and
                 not is_nil(conversation.latest_message_id) and
                 (is_nil(last_read_message_id) or
                    last_read_message_id != conversation.latest_message_id)
             )
    end
  end

  policies do
    # Read floor is contributed by WorkspaceTenanted (workspace membership).
    # Joining / cursor updates are workspace-member actions.
    policy action_type([:create, :update]) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :conversation_id, :uuid, allow_nil?: false, public?: true
    attribute :membership_id, :uuid, allow_nil?: false, public?: true

    attribute :last_read_message_id, :uuid do
      public? true
      allow_nil? true

      description "The last message this participant has read; powers the unread/inbox projection."
    end

    timestamps()
  end

  relationships do
    belongs_to :conversation, Concept.Knowledge.Chat.Conversation,
      source_attribute: :conversation_id,
      destination_attribute: :id,
      define_attribute?: false

    belongs_to :membership, Concept.Accounts.Membership,
      source_attribute: :membership_id,
      destination_attribute: :id,
      define_attribute?: false
  end

  calculations do
    # Identity kind, DERIVED from the membership's role — never stored.
    # role :agent → :agent ; otherwise → :user.
    calculate :kind,
              :atom,
              expr(if(membership.role == :agent, do: :agent, else: :user))
  end

  identities do
    identity :unique_membership_per_conversation, [:conversation_id, :membership_id]
  end
end
