defmodule Concept.Knowledge.Chat.Message.Changes.CreateConversationIfNotProvided do
  @moduledoc """
  Routes a message to its conversation. Resolution order:

    1. explicit `conversation_id` argument → post there;
    2. else find the host's conversation (`host_type`/`host_id`) → post there;
    3. else create the host's conversation, then post there.

  This is the host-model generalization of the original behaviour (which only
  knew the `:workspace` host). It is what lets EVERY registered `Concept.Hostable`
  be conversable through the single `Message.:create` action — no per-host
  `discuss` action, no parallel wiring. `use Concept.Hostable` is pure opt-in:
  it admits a resource's type into the valid `host_type` set and supplies the
  grounding scope; the conversational power lives here, once.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    if changeset.arguments[:conversation_id] do
      Ash.Changeset.force_change_attribute(
        changeset,
        :conversation_id,
        changeset.arguments.conversation_id
      )
    else
      Ash.Changeset.before_action(changeset, fn changeset ->
        conversation = resolve_host_conversation(changeset, context)
        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation.id)
      end)
    end
  end

  # Find-or-create the conversation for the addressed host. Defaults to the
  # :workspace host (host_id nil) — exactly the pre-host-model behaviour.
  defp resolve_host_conversation(changeset, context) do
    host_type = Ash.Changeset.get_argument(changeset, :host_type) || :workspace
    host_id = Ash.Changeset.get_argument(changeset, :host_id)

    opts = Ash.Context.to_opts(context)

    workspace_id =
      Ash.ToTenant.to_tenant(changeset.tenant, Concept.Knowledge.Chat.Conversation)

    case Concept.Knowledge.Chat.conversations_for_host(host_type, host_id, opts) do
      {:ok, [conversation | _]} ->
        conversation

      _ ->
        Concept.Knowledge.Chat.create_conversation!(
          %{workspace_id: workspace_id, host_type: host_type, host_id: host_id},
          opts
        )
    end
  end
end
