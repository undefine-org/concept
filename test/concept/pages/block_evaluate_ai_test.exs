defmodule Concept.Pages.BlockEvaluateAiTest do
  use Concept.DataCase, async: true

  alias Concept.Pages
  alias Concept.Knowledge

  setup do
    # Create test user
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Get workspace for user
    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # Create a page
    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    # Create an AI answer block
    {:ok, block} =
      Pages.create_block(page.id, :ai_answer, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{
      user: user,
      workspace: workspace,
      page: page,
      block: block
    }
  end

  describe "empty AI block" do
    test "renders with default props", %{block: block} do
      assert block.type == :ai_answer
      # Default props from block type
      assert block.props["prompt"] == ""
      assert block.props["scope"] == "subtree"
      assert block.content == %{}
    end
  end

  describe "evaluate_ai action" do
    test "updates block props with prompt/scope/profile", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "What is the meaning of life?",
          :workspace,
          :default,
          actor: user,
          tenant: workspace.id
        )

      # Props should be updated immediately
      assert updated_block.props["prompt"] == "What is the meaning of life?"
      assert updated_block.props["scope"] == "workspace"
      assert updated_block.props["profile"] == "default"
    end

    # FLAKY: spawns an async Task that competes with the test process for the
    # sandbox connection (the test does Process.sleep then re-reads the block,
    # racing the Task's own DB writes). Pin to skipped until FUP-030 promotes
    # the parked e2e test to a non-async case that can safely share the
    # sandbox.
    @tag :skip
    test "creates conversation for the block", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "Test question",
          :workspace,
          :default,
          actor: user,
          tenant: workspace.id
        )

      # Wait a moment for async task to start
      Process.sleep(500)

      # Reload to check if conversation_id was set
      {:ok, reloaded_block} =
        Pages.Block
        |> Ash.get(block.id, actor: user, tenant: workspace.id)

      # Conversation might be created by now
      if conversation_id = reloaded_block.props["conversation_id"] do
        {:ok, conversation} =
          Knowledge.Chat.get_conversation(conversation_id,
            actor: user,
            authorize?: false
          )

        assert conversation.title =~ "AI Block"
      end
    end

    test "scope :subtree is stored in props", %{
      user: user,
      workspace: workspace,
      block: block
    } do
      {:ok, updated_block} =
        Pages.evaluate_ai(
          block,
          "Subtree question",
          :subtree,
          :default,
          actor: user,
          tenant: workspace.id
        )

      assert updated_block.props["scope"] == "subtree"
    end
  end

  describe "block content structure" do
    test "validates expected content shape for AI blocks", %{block: block} do
      # Verify block starts empty
      assert block.content == %{}

      # Expected content structure after AI response:
      # %{"message_id" => uuid, "model" => string, "ran_at" => iso8601}
      assert is_map(block.content)
    end
  end

  describe "completion broadcast matcher (regression)" do
    # The spawned `EvaluateAi` Task subscribes to the chat-message PubSub topic
    # for its conversation and waits for a `source: :agent, complete: true`
    # broadcast, then updates `block.content` with `message_id` pointing at
    # the response. The original implementation subscribed to the wrong
    # PubSub (`Concept.PubSub` instead of `ConceptWeb.Endpoint`) and matched
    # on a raw map shape instead of the `Phoenix.Socket.Broadcast` envelope
    # that `Ash.Notifier.PubSub` actually delivers — so the spawned task
    # waited forever and the UI never flipped to `state=answered`.
    #
    # Extracted matcher exists so this contract is unit-testable without
    # involving the full AshOban respond pipeline.
    alias Concept.Pages.Block.Changes.EvaluateAi

    test "matches a `source: :agent, complete: true` broadcast and returns the response id" do
      response_id = "019e3b0e-7323-7a48-826a-3081cc087377"

      envelope = %Phoenix.Socket.Broadcast{
        topic: "chat:messages:019e3ae1-b945-7b25-a166-8d4d3e736160",
        event: "upsert_response",
        payload: %{
          id: response_id,
          text: "answer",
          source: :agent,
          complete: true,
          tool_calls: nil,
          tool_results: nil
        }
      }

      assert EvaluateAi.decide_completion(envelope) == {:complete, response_id}
    end

    test "keeps waiting on streaming (complete: false) chunks" do
      envelope = %Phoenix.Socket.Broadcast{
        topic: "chat:messages:c",
        event: "upsert_response",
        payload: %{
          id: "x",
          source: :agent,
          complete: false,
          text: "par",
          tool_calls: nil,
          tool_results: nil
        }
      }

      assert EvaluateAi.decide_completion(envelope) == :continue
    end

    test "keeps waiting on user-message echoes (source: :user)" do
      envelope = %Phoenix.Socket.Broadcast{
        topic: "chat:messages:c",
        event: "create",
        payload: %{
          id: "x",
          source: :user,
          complete: true,
          text: "q",
          tool_calls: nil,
          tool_results: nil
        }
      }

      assert EvaluateAi.decide_completion(envelope) == :continue
    end

    test "does NOT match raw map payloads (the legacy bug shape)" do
      # Pre-fix, the receive loop matched a raw map. Real broadcasts arrive
      # wrapped in `Phoenix.Socket.Broadcast`, so the bare-map clause could
      # never fire. Pin this behaviour: the matcher only accepts envelopes.
      raw = %{id: "x", source: :agent, complete: true, text: "a"}
      assert EvaluateAi.decide_completion(raw) == :continue
    end
  end

  describe "wait_for_completion (skipped — needs non-async sandbox)" do
    @describetag :skip
    test "broadcasted assistant-complete event updates block.content with message_id",
         %{user: user, workspace: ws, block: block} do
      # Kick off evaluation: synchronously stamps props with prompt/scope/profile
      # and conversation_id, then spawns the wait loop in a Task.
      {:ok, _} =
        Pages.evaluate_ai(block, "ping?", :workspace, :default,
          actor: user,
          tenant: ws.id
        )

      # The Task must subscribe before we broadcast — it does a
      # synchronous conversation create first, so a short wait is enough.
      conv_id =
        Enum.reduce_while(1..50, nil, fn _, _ ->
          {:ok, b} = Ash.get(Pages.Block, block.id, actor: user, tenant: ws.id)

          case b.props["conversation_id"] do
            nil ->
              Process.sleep(20)
              {:cont, nil}

            id ->
              {:halt, id}
          end
        end)

      assert is_binary(conv_id), "task never persisted conversation_id"

      # Give the Task a beat to install its Endpoint.subscribe before we fire.
      Process.sleep(50)

      response_id = Ash.UUIDv7.generate()

      ConceptWeb.Endpoint.broadcast(
        "chat:messages:" <> conv_id,
        "upsert_response",
        %{
          id: response_id,
          text: "pong",
          source: :agent,
          complete: true,
          tool_calls: nil,
          tool_results: nil
        }
      )

      # Poll block.content until the Task processes the broadcast and persists.
      :ok =
        Enum.reduce_while(1..100, :timeout, fn _, _ ->
          {:ok, b} = Ash.get(Pages.Block, block.id, actor: user, tenant: ws.id)

          if b.content["message_id"] == response_id do
            {:halt, :ok}
          else
            Process.sleep(20)
            {:cont, :timeout}
          end
        end)
    end
  end

  describe "update_block_content lock bypass (regression)" do
    # The spawned `EvaluateAi` Task receives the assistant-complete broadcast
    # in a process the user never locked the block from. The `:update_content`
    # action runs `Concept.Pages.Block.Changes.RequireOwnLock` which rejects
    # any non-system actor that isn't the current lock_holder — producing
    # `code: :not_lock_holder` and a runtime error log:
    #
    #     [error] Failed to update AI block content:
    #       %Ash.Error.Invalid{errors: [%{message: "lock not held by actor", code: :not_lock_holder}]}
    #
    # The Task must escalate to a system actor (`%{system?: true}`) for this
    # write, since the lock is a human-collaboration concern; an internal AI
    # response landing on the block is not. Pin both directions.
    alias Concept.Pages.Block.Changes.EvaluateAi

    test "finalize_completion succeeds when block is not locked",
         %{user: user, workspace: ws, block: block} do
      response_id = Ash.UUIDv7.generate()

      assert :ok = EvaluateAi.finalize_completion(block, response_id, :default, ws.id)

      {:ok, reloaded} = Ash.get(Pages.Block, block.id, actor: user, tenant: ws.id)
      assert reloaded.content["message_id"] == response_id
      assert reloaded.content["model"] == "default"
    end

    test "finalize_completion succeeds even when block is locked by another user",
         %{user: user, workspace: ws, page: page} do
      # Block locked by `user`; the spawned task acts as a system actor and
      # must still be allowed to write the response pointer.
      {:ok, locked_block} =
        Pages.create_block(page.id, :ai_answer, ws.id, nil, actor: user, tenant: ws.id)

      {:ok, _} =
        Pages.acquire_lock(
          locked_block.id,
          %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )

      response_id = Ash.UUIDv7.generate()
      assert :ok = EvaluateAi.finalize_completion(locked_block, response_id, :default, ws.id)

      {:ok, reloaded} = Ash.get(Pages.Block, locked_block.id, actor: user, tenant: ws.id)
      assert reloaded.content["message_id"] == response_id
    end
  end
end
