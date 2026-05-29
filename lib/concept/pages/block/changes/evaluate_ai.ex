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

    # 3. Subscribe to chat-message PubSub BEFORE creating the message.
    # `Message.create` enqueues the `:respond` Oban job; if that job lands the
    # completion broadcast before we subscribe, the message is missed and we
    # block until the 5-minute timeout (TOCTOU). Subscribing first closes the
    # window. Messages broadcast via `ConceptWeb.Endpoint` (see Message's
    # `pub_sub do module …` block), NOT `Concept.PubSub`.
    topic = "chat:messages:" <> conversation_id
    ConceptWeb.Endpoint.subscribe(topic)

    # 4. Create message (triggers AshAI respond pipeline).
    # Ash 3.x rejects `set_argument/3` after `for_create/3` (the changeset is
    # already validated). Set the argument first, then build the action.
    {:ok, message} =
      Concept.Knowledge.Chat.Message
      |> Ash.Changeset.new()
      |> Ash.Changeset.set_argument(:conversation_id, conversation_id)
      |> Ash.Changeset.for_create(:create, %{
        text: prompt,
        scope: scope,
        scope_target_id: scope_target_id,
        profile: profile
      })
      |> Ash.create(actor: actor, authorize?: false)

    # 5. Belt-and-suspenders: a fast respond job may have completed before the
    # broadcast was wired (or between create and now). Poll once for an
    # already-complete response before entering the receive loop.
    case poll_complete_response(message, tenant) do
      {:complete, response_id} -> finalize_completion(block, response_id, profile, tenant)
      :none -> wait_for_completion(block, message, profile, tenant)
    end
  end

  # One-shot check for an already-complete assistant response to a user message.
  # Guards against the create→subscribe race when the respond job is fast.
  defp poll_complete_response(user_message, tenant) do
    Concept.Knowledge.Chat.Message
    |> Ash.Query.filter(response_to_id == ^user_message.id and complete == true)
    |> Ash.Query.limit(1)
    |> Ash.read(actor: %{system?: true}, tenant: tenant, authorize?: false)
    |> case do
      {:ok, [%{id: response_id} | _]} -> {:complete, response_id}
      _ -> :none
    end
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
      block
      |> Ash.Changeset.for_update(:update_props, %{
        props: Map.put(block.props || %{}, "conversation_id", conversation.id)
      })
      |> Ash.update!(authorize?: false, tenant: block.workspace_id)
    rescue
      _ -> :ok
    end

    conversation.id
  end

  defp wait_for_completion(block, user_message, profile, tenant) do
    receive do
      msg ->
        case decide_completion(msg) do
          {:complete, response_id} ->
            finalize_completion(block, response_id, profile, tenant)

          :continue ->
            wait_for_completion(block, user_message, profile, tenant)
        end
    after
      300_000 ->
        :timeout
    end
  end

  @doc """
  Pure predicate over received messages. Returns `{:complete, response_id}`
  when the message is a fully-complete assistant response broadcast (via
  `ConceptWeb.Endpoint` + `Ash.Notifier.PubSub`), `:continue` otherwise.

  Public so it can be unit-tested without spinning the whole Task.
  """
  def decide_completion(%Phoenix.Socket.Broadcast{
        topic: "chat:messages:" <> _,
        payload: %{source: :agent, complete: true, id: response_id}
      }),
      do: {:complete, response_id}

  def decide_completion(_), do: :continue

  @doc """
  Persist the assistant response pointer (`message_id`) onto the AI Answer
  block. Called from the spawned wait loop once the assistant message is
  complete.

  Uses `%{system?: true}` as the actor so the `RequireOwnLock` change on
  `:update_content` accepts the write: the spawned Task runs in a process
  the user never locked from, and AI-response landings are not a human
  collaboration concern that the lock is protecting against. The lock
  remains in force for human edits of the block.

  Public so this contract is reachable from regression tests without
  driving the full receive loop.
  """
  def finalize_completion(block, message_id, profile, tenant) do
    content = %{
      "message_id" => message_id,
      "model" => Atom.to_string(profile),
      "ran_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Actor/tenant must be set on the changeset *before* the action runs:
    # `Concept.Pages.Block.Changes.RequireOwnLock` reads `ctx.actor` during
    # `change/3`, which is populated from the changeset's context. Passing
    # `actor:` only to `Ash.update!/2` arrives too late — the lock check has
    # already fired with `ctx.actor == nil`.
    try do
      block
      |> Ash.Changeset.for_update(:update_content, %{content: content},
        actor: %{system?: true},
        tenant: tenant
      )
      |> Ash.update!(authorize?: false)

      :ok
    rescue
      e ->
        require Logger
        Logger.error("Failed to update AI block content: #{inspect(e)}")
        :error
    end
  end
end
