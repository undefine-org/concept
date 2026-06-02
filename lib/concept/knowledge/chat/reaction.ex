defmodule Concept.Knowledge.Chat.Reaction do
  @moduledoc """
  An emoji reaction on a message: the join of a `Membership` (the reactor's
  identity) × a `Message` × an emoji. The structural twin of `Participant` —
  an identity-keyed join — so "who reacted with what" is real, parity-exposed,
  and reusable by agents (an agent member can 👍 a message via MCP).

  One reaction per (message, membership, emoji): re-reacting is idempotent
  (upsert), and `unreact` removes it (owner-scoped). Cross-user real-time sync
  is deferred — the chat UI refreshes reactions locally on react/unreact; a
  PubSub broadcast on the per-conversation topic is a follow-up.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Knowledge.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chat_reactions"
    repo Concept.Repo

    references do
      reference :message, on_delete: :delete
      reference :membership, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :message_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :react do
      description "Add an emoji reaction to a message (idempotent: re-reacting is a no-op)."
      upsert? true
      upsert_identity :unique_reaction

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the reaction belongs to."

      argument :message_id, :uuid,
        allow_nil?: false,
        description: "The message being reacted to."

      argument :membership_id, :uuid,
        allow_nil?: false,
        description: "Membership (identity) of the reactor."

      argument :emoji, :string,
        allow_nil?: false,
        description: "The emoji, e.g. \"👍\"."

      change set_attribute(:workspace_id, arg(:workspace_id))
      change set_attribute(:message_id, arg(:message_id))
      change set_attribute(:membership_id, arg(:membership_id))
      change set_attribute(:emoji, arg(:emoji))
    end

    destroy :unreact do
      description "Remove a previously added emoji reaction from a message."
    end

    read :for_message do
      description "List the reactions on a message."

      argument :message_id, :uuid,
        allow_nil?: false,
        description: "Message whose reactions to load."

      filter expr(message_id == ^arg(:message_id))
    end

    read :for_conversation do
      description "List all reactions on the messages of a conversation."

      argument :conversation_id, :uuid,
        allow_nil?: false,
        description: "Conversation whose message reactions to load."

      filter expr(message.conversation_id == ^arg(:conversation_id))
    end
  end

  policies do
    # Read floor from WorkspaceTenanted (workspace membership). Reacting is a
    # workspace-member action.
    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    # Unreacting (destroy) requires OWNERSHIP: you may only remove your own
    # reaction, not another member's. The workspace-member floor alone would let
    # any member destroy any reaction via the parity-exposed unreact tool; the
    # ownership filter ties the row's membership to the acting user.
    policy action_type(:destroy) do
      authorize_if expr(membership.user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :message_id, :uuid, allow_nil?: false, public?: true
    attribute :membership_id, :uuid, allow_nil?: false, public?: true

    attribute :emoji, :string do
      allow_nil? false
      public? true
      description "The emoji glyph, e.g. \"👍\"."
    end

    timestamps()
  end

  relationships do
    belongs_to :message, Concept.Knowledge.Chat.Message,
      source_attribute: :message_id,
      destination_attribute: :id,
      define_attribute?: false

    belongs_to :membership, Concept.Accounts.Membership,
      source_attribute: :membership_id,
      destination_attribute: :id,
      define_attribute?: false
  end

  identities do
    identity :unique_reaction, [:message_id, :membership_id, :emoji]
  end
end
