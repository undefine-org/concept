defmodule Concept.Pages.Block.Changes.EvaluateAi do
  @moduledoc """
  Evaluate an AI block: create/find conversation, send message, spawn async task
  to monitor completion, update block.content when done.
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    prompt = Ash.Changeset.get_argument(changeset, :prompt)
    scope = Ash.Changeset.get_argument(changeset, :scope) || :workspace
    profile = Ash.Changeset.get_argument(changeset, :profile) || :default

    actor = context.actor
    tenant = context.tenant

    if is_nil(actor) or is_nil(tenant) do
      Ash.Changeset.add_error(changeset, "Actor and tenant required for evaluate_ai")
    else
      # Spawn async task to handle conversation + message creation + monitoring
      Task.Supervisor.start_child(Concept.TaskSupervisor, fn ->
        handle_evaluation(changeset.data, prompt, scope, profile, actor, tenant)
      end)

      # Update props to store current prompt/scope/profile for refresh
      new_props =
        (changeset.data.props || %{})
        |> Map.put("prompt", prompt)
        |> Map.put("scope", Atom.to_string(scope))
        |> Map.put("profile", Atom.to_string(profile))

      Ash.Changeset.force_change_attribute(changeset, :props, new_props)
    end
  end

  defp handle_evaluation(block, prompt, scope, profile, actor, tenant) do
    # 1. Find or create conversation for this block
    conversation_id = get_or_create_conversation(block, actor, tenant)

    # 2. Determine scope_target_id based on scope
    scope_target_id =
      case scope do
        :page -> block.page_id
        :subtree -> block.id
        :workspace -> nil
      end

    # 3. Create message (triggers AshAI respond pipeline)
    # Build changeset and set conversation_id argument
    {:ok, message} =
      Concept.Knowledge.Chat.Message
      |> Ash.Changeset.for_create(:create, %{
        text: prompt,
        scope: scope,
        scope_target_id: scope_target_id,
        profile: profile
      })
      |> Ash.Changeset.set_argument(:conversation_id, conversation_id)
      |> Ash.create(actor: actor, authorize?: false)

    # 4. Subscribe to conversation PubSub and wait for completion
    topic = "chat:messages:" <> conversation_id
    Phoenix.PubSub.subscribe(Concept.PubSub, topic)

    # Wait for the assistant response to complete
    wait_for_completion(block, message, profile, tenant)
  end

  defp get_or_create_conversation(block, actor, tenant) do
    # Check if block.props already has conversation_id
    existing_id = get_in(block.props, ["conversation_id"])

    if existing_id do
      # Verify it exists
      case Concept.Knowledge.Chat.get_conversation(existing_id, actor: actor, authorize?: false) do
        {:ok, _conv} -> existing_id
        {:error, _} -> create_conversation(block, actor, tenant)
      end
    else
      create_conversation(block, actor, tenant)
    end
  end

  defp create_conversation(block, actor, _tenant) do
    block_short = binary_part(block.id, 0, 8)
    title = "AI Block #{block_short}"

    {:ok, conversation} =
      Concept.Knowledge.Chat.create_conversation(
        %{title: title},
        actor: actor,
        authorize?: false
      )

    # Update block props with conversation_id (best-effort)
    try do
      Concept.Pages.Block
      |> Ash.Changeset.for_update(:update_props, block, %{
        props: Map.put(block.props || %{}, "conversation_id", conversation.id)
      })
      |> Ash.update!(authorize?: false, tenant: block.workspace_id)
    rescue
      _ -> :ok
    end

    conversation.id
  end

  defp wait_for_completion(block, user_message, profile, tenant) do
    # The assistant's response will be created with response_to_id pointing to user_message
    # We need to wait for the assistant message to complete
    receive do
      %{
        text: _text,
        id: response_id,
        source: :agent,
        complete: true
      } ->
        # Update block content with message_id pointer
        update_block_content(block, response_id, profile, tenant)

      _ ->
        # Ignore other messages and keep waiting
        wait_for_completion(block, user_message, profile, tenant)
    after
      300_000 ->
        # 5 minute timeout
        :timeout
    end
  end

  defp update_block_content(block, message_id, profile, tenant) do
    content = %{
      "message_id" => message_id,
      "model" => Atom.to_string(profile),
      "ran_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    try do
      Concept.Pages.Block
      |> Ash.Changeset.for_update(:update_content, block, %{content: content})
      |> Ash.update!(authorize?: false, tenant: tenant)
    rescue
      e ->
        require Logger
        Logger.error("Failed to update AI block content: #{inspect(e)}")
        :error
    end
  end
end
