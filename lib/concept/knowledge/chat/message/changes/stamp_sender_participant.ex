defmodule Concept.Knowledge.Chat.Message.Changes.StampSenderParticipant do
  @moduledoc """
  Stamp a human-sent message with its author's `sender_participant_id`.

  The field is the canonical sender identity (NULL = the host's grounded voice
  spoke; see `Participant` moduledoc). It was previously populated only for
  agents — humans sent anonymously, so a projection could not tell *which*
  member spoke, and the chat UI could not distinguish "me" from another person
  (every human bubble looked identical). This change makes the field honest for
  humans too: the sender is resolved to its `Participant` (idempotent upsert,
  the same join `JoinSenderAsParticipant` performs) and stamped before insert.

  Runs in `before_action` **after** `CreateConversationIfNotProvided` (so the
  `conversation_id` attribute is resolved). Host turns flow through
  `:upsert_response`, never this `:create` path, so they are never stamped.
  Best-effort: any resolution failure leaves the field NULL (the message still
  sends and renders as an unattributed member — never falsely as "me").
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with %{} = actor <- context.actor,
           actor_id when is_binary(actor_id) <- Map.get(actor, :id),
           conversation_id when is_binary(conversation_id) <-
             Ash.Changeset.get_attribute(changeset, :conversation_id),
           tenant when not is_nil(tenant) <- changeset.tenant,
           {:ok, membership} <- membership_for(actor_id, tenant),
           {:ok, participant} <- upsert_participant(membership, conversation_id, tenant, actor) do
        Ash.Changeset.force_change_attribute(changeset, :sender_participant_id, participant.id)
      else
        _ -> changeset
      end
    end)
  end

  defp upsert_participant(membership, conversation_id, tenant, actor) do
    Concept.Knowledge.Chat.join_conversation(
      %{
        workspace_id: workspace_id(tenant),
        conversation_id: conversation_id,
        membership_id: membership.id
      },
      actor: actor,
      tenant: tenant
    )
  end

  defp workspace_id(tenant),
    do: Ash.ToTenant.to_tenant(tenant, Concept.Knowledge.Chat.Conversation)

  defp membership_for(user_id, tenant) do
    Concept.Accounts.Membership
    |> Ash.Query.filter(workspace_id == ^workspace_id(tenant) and user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{} = m} -> {:ok, m}
      _ -> :error
    end
  end
end
