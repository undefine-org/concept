defmodule Concept.Knowledge.Chat.Message.Changes.CreateConversationIfNotProvided do
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
        # Conversation is workspace-tenanted: forward the message's tenant as the
        # conversation's workspace_id argument (BUG-061).
        opts = Ash.Context.to_opts(context)
        workspace_id = Ash.ToTenant.to_tenant(changeset.tenant, Concept.Knowledge.Chat.Conversation)

        conversation =
          Concept.Knowledge.Chat.create_conversation!(
            %{workspace_id: workspace_id},
            opts
          )

        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation.id)
      end)
    end
  end
end
