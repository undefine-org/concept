defmodule Concept.Knowledge.Chat do
  use Ash.Domain,
    otp_app: :concept,
    extensions: [AshAi, AshPhoenix, Concept.AutoTools]

  resources do
    resource Concept.Knowledge.Chat.Conversation do
      define :create_conversation, action: :create
      define :get_conversation, action: :read, get_by: [:id]
      define :my_conversations
      define :inbox
      define :conversations_for_host, action: :for_host, args: [:host_type, :host_id]
      define :thread_for_seed, action: :for_seed, args: [:seed_message_id]
      define :decrement_budget, action: :decrement_budget
      define :replenish_budget, action: :replenish_budget
      define :mark_crystallized, action: :mark_crystallized

      define :crystallize_conversation,
        action: :crystallize,
        args: [:conversation_id, :target_page_id, :workspace_id]
    end

    resource Concept.Knowledge.Chat.Message do
      define :message_history,
        action: :for_conversation,
        args: [:conversation_id],
        default_options: [query: [sort: [inserted_at: :desc]]]

      define :create_message, action: :create
      define :get_message, action: :read, get_by: [:id]
    end

    resource Concept.Knowledge.Chat.Participant do
      define :join_conversation, action: :join
      define :participants_for_conversation, action: :for_conversation, args: [:conversation_id]
      define :mark_participant_read, action: :mark_read
    end

    resource Concept.Knowledge.Chat.Reaction do
      define :react, action: :react
      define :unreact, action: :unreact
      define :reactions_for_message, action: :for_message, args: [:message_id]
      define :reactions_for_conversation, action: :for_conversation, args: [:conversation_id]
    end
  end
end
