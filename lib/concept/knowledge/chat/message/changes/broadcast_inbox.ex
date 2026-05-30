defmodule Concept.Knowledge.Chat.Message.Changes.BroadcastInbox do
  @moduledoc """
  After a message is created, notify every participant of the conversation on
  their personal inbox topic `inbox:<user_id>` (PLAN-010 §A): the recipient-keyed
  feed that powers a cross-conversation unread badge. The existing per-conversation
  topic only reaches clients already viewing that conversation; this reaches a
  user anywhere in the app.

  Best-effort: a broadcast failure never fails the message send.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      broadcast(message)
      {:ok, message}
    end)
  end

  defp broadcast(message) do
    {:ok, participants} =
      Concept.Knowledge.Chat.participants_for_conversation(message.conversation_id,
        authorize?: false,
        tenant: message.workspace_id
      )

    payload = %{conversation_id: message.conversation_id, message_id: message.id}

    participants
    |> Ash.load!([:membership], authorize?: false, tenant: message.workspace_id)
    |> Enum.each(fn participant ->
      user_id = participant.membership && participant.membership.user_id

      if user_id do
        Phoenix.PubSub.broadcast(
          Concept.PubSub,
          "inbox:#{user_id}",
          {:inbox_activity, payload}
        )
      end
    end)

    :ok
  rescue
    _ -> :ok
  end
end
