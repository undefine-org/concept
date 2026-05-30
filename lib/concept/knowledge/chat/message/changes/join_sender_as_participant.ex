defmodule Concept.Knowledge.Chat.Message.Changes.JoinSenderAsParticipant do
  @moduledoc """
  After a member sends a message, ensure they are a Participant of the
  conversation (idempotent upsert). The Participant carries the unread cursor
  that powers the inbox (PLAN-010 §39, Wave 4).

  Only human/agent senders are joined — a host turn (the grounded AI voice) has
  no identity and is never a participant. Host turns run under the addresser's
  actor via `authorize?: false` (see Respond) and do not flow through this
  change's `:create` action path in a way that should self-join.

  Best-effort: a failure to join must not fail the message send. Resolution of
  the actor's membership uses the conversation's workspace tenant.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, message ->
      maybe_join(message, context)
      {:ok, message}
    end)
  end

  defp maybe_join(message, context) do
    actor = context.actor
    tenant = message.workspace_id

    with true <- is_map(actor),
         actor_id when is_binary(actor_id) <- Map.get(actor, :id),
         {:ok, membership} <- membership_for(actor_id, tenant) do
      Concept.Knowledge.Chat.join_conversation(
        %{
          workspace_id: tenant,
          conversation_id: message.conversation_id,
          membership_id: membership.id
        },
        actor: actor,
        tenant: tenant
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  defp membership_for(user_id, workspace_id) do
    Concept.Accounts.Membership
    |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{} = m} -> {:ok, m}
      _ -> :error
    end
  end
end
