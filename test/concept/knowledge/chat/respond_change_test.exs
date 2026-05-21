defmodule Concept.Knowledge.Chat.RespondChangeTest do
  @moduledoc """
  Regression suite for `Concept.Knowledge.Chat.Message.Changes.Respond` and
  the `Concept.LLM.ReqLLMTap` usage adapter.

  Covers:
    * BUG-045 — `:done` event with `%AshAi.ToolLoop.Result{}` must not crash.
    * BUG-046 — token usage must propagate from streaming responses into
      the persisted `prompt_tokens` / `completion_tokens` columns.
    * FUP-028 — re-invoking `:respond` after a partial stream must not
      re-call the LLM; partial replies are finalized with an "interrupted"
      suffix.
  """

  use Concept.DataCase, async: false

  alias Concept.Knowledge.Chat
  alias Concept.Knowledge.Chat.Message.Changes.Respond
  alias Concept.LLM.ReqLLMTap
  alias Concept.TestSupport.MockReqLLM

  # ──────────────────────────────────────────────────────────────────────
  # Pure / unit tests — no DB
  # ──────────────────────────────────────────────────────────────────────

  describe "extract_done_metadata/1 — BUG-045 regression" do
    test "returns empty map for %AshAi.ToolLoop.Result{} without raising" do
      result = %AshAi.ToolLoop.Result{
        messages: [],
        final_text: "hi",
        iterations: 1,
        tool_calls_made: []
      }

      assert Respond.extract_done_metadata(result) == %{}
    end

    test "returns empty map for other arbitrary structs" do
      assert Respond.extract_done_metadata(%URI{}) == %{}
    end

    test "extracts fields from a plain map carrying :usage and :grounding_metadata" do
      metadata = %{
        usage: %{prompt_tokens: 11, completion_tokens: 5},
        grounding_metadata: %{grounding_score: 0.87}
      }

      assert %{
               prompt_tokens: 11,
               completion_tokens: 5,
               grounding_score: 0.87
             } = Respond.extract_done_metadata(metadata)
    end

    test "returns empty map for non-map input" do
      assert Respond.extract_done_metadata(nil) == %{}
      assert Respond.extract_done_metadata(:done) == %{}
      assert Respond.extract_done_metadata("oops") == %{}
    end
  end

  describe "interrupted_text/1" do
    test "appends suffix to plain text" do
      assert Respond.interrupted_text("Hello") == "Hello\n\n[response interrupted]"
    end

    test "is idempotent — never appends twice" do
      once = Respond.interrupted_text("Hello")
      assert Respond.interrupted_text(once) == once
    end

    test "handles nil by returning the trimmed suffix" do
      assert Respond.interrupted_text(nil) == "[response interrupted]"
    end
  end

  describe "ReqLLMTap.aggregate/1 — BUG-046 unit" do
    test "sums input/output tokens across calls" do
      usages = [
        %{input_tokens: 12, output_tokens: 7},
        %{input_tokens: 5, output_tokens: 3}
      ]

      assert ReqLLMTap.aggregate(usages) == %{
               prompt_tokens: 17,
               completion_tokens: 10
             }
    end

    test "omits keys when all values are 0 or missing" do
      assert ReqLLMTap.aggregate([]) == %{}
      assert ReqLLMTap.aggregate([%{}]) == %{}
      assert ReqLLMTap.aggregate([%{input_tokens: 0, output_tokens: 0}]) == %{}
    end

    test "tolerates missing or non-integer fields without raising" do
      usages = [%{input_tokens: 4}, %{output_tokens: 6}, %{input_tokens: nil}]
      assert ReqLLMTap.aggregate(usages) == %{prompt_tokens: 4, completion_tokens: 6}
    end
  end

  describe "ReqLLMTap.collected_usage/0" do
    setup do
      on_exit(&ReqLLMTap.reset/0)
      :ok
    end

    test "returns [] when not registered" do
      assert ReqLLMTap.collected_usage() == []
    end

    test "captures usage from a real-looking StreamResponse round-trip via the mock" do
      MockReqLLM.set_reply(text: "ok", input_tokens: 9, output_tokens: 4)
      :ok = ReqLLMTap.register()

      # Drive a stream through the tap end-to-end (delegate → MockReqLLM).
      Application.put_env(:concept, :req_llm_module, MockReqLLM)
      on_exit(fn -> Application.delete_env(:concept, :req_llm_module) end)

      {:ok, stream_response} = ReqLLMTap.stream_text("any:model", [], [])

      # Stream consumption is what unblocks MetadataHandle.await/2.
      _ = Enum.to_list(stream_response.stream)

      assert [%{input_tokens: 9, output_tokens: 4}] = ReqLLMTap.collected_usage()
    end
  end

  describe "ReqLLMTap.collected_grounding_score/0" do
    setup do
      Application.put_env(:concept, :req_llm_module, MockReqLLM)
      MockReqLLM.reset()

      on_exit(fn ->
        Application.delete_env(:concept, :req_llm_module)
        ReqLLMTap.reset()
      end)

      :ok = ReqLLMTap.register()
      :ok
    end

    test "returns nil when no grounding metadata was observed" do
      MockReqLLM.set_reply(text: "x")
      {:ok, sr} = ReqLLMTap.stream_text("m", [], [])
      _ = Enum.to_list(sr.stream)

      assert ReqLLMTap.collected_grounding_score() == nil
    end

    test "averages confidenceScores from a flat list" do
      MockReqLLM.set_reply(text: "x", grounding_confidences: [0.6, 0.8, 1.0])
      {:ok, sr} = ReqLLMTap.stream_text("m", [], [])
      _ = Enum.to_list(sr.stream)

      assert_in_delta ReqLLMTap.collected_grounding_score(), 0.8, 1.0e-9
    end

    test "flattens nested groundingSupports[] confidenceScores arrays" do
      MockReqLLM.set_reply(text: "x", grounding_confidences: [[0.4, 0.6], [0.8]])
      {:ok, sr} = ReqLLMTap.stream_text("m", [], [])
      _ = Enum.to_list(sr.stream)

      # (0.4 + 0.6 + 0.8) / 3
      assert_in_delta ReqLLMTap.collected_grounding_score(), 0.6, 1.0e-9
    end
  end

  describe "ReqLLMTap contract — stream consumed in caller pid" do
    setup do
      Application.put_env(:concept, :req_llm_module, MockReqLLM)
      MockReqLLM.reset()
      MockReqLLM.set_reply(text: "ok", input_tokens: 1, output_tokens: 1)
      on_exit(fn -> Application.delete_env(:concept, :req_llm_module) end)
      :ok
    end

    test "AshAi.ToolLoop.stream invokes req_llm.stream_text in the consumer pid" do
      caller = self()

      _ =
        [ReqLLM.Context.user("hi")]
        |> AshAi.ToolLoop.stream(
          otp_app: :concept,
          tools: false,
          model: "google:gemini-2.5-flash",
          req_llm: ReqLLMTap
        )
        |> Enum.to_list()

      assert MockReqLLM.stream_text_pid() == caller,
             """
             ReqLLMTap depends on the underlying ReqLLM call running in the
             consumer pid (so Process.dict-based stash survives across the
             stream lifecycle). If this assertion fails, ash_ai has changed
             its stream consumption model — see Concept.LLM.ReqLLMTap docs.
             """
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Integration tests — DB + mocked LLM
  # ──────────────────────────────────────────────────────────────────────

  describe "existing_response_decision/1 — FUP-028" do
    setup :base_fixtures

    test ":stream when no response exists", %{user_message: msg} do
      assert Respond.existing_response_decision(msg) == :stream
    end

    test ":noop when a completed response already exists", %{user_message: msg} = ctx do
      _ = upsert_agent_reply!(msg, ctx, text: "Done.", complete: true)

      assert Respond.existing_response_decision(msg) == :noop
    end

    test "{:finalize, partial} when a partial response exists",
         %{user_message: msg} = ctx do
      partial = upsert_agent_reply!(msg, ctx, text: "partial...", complete: false)

      assert {:finalize, found} = Respond.existing_response_decision(msg)
      assert found.id == partial.id
      refute found.complete
    end
  end

  describe ":respond action — full pipeline with mock LLM" do
    setup :base_fixtures

    setup do
      Application.put_env(:concept, :req_llm_module, MockReqLLM)
      MockReqLLM.reset()
      MockReqLLM.set_reply(text: "Hello!", input_tokens: 12, output_tokens: 7)
      on_exit(fn -> Application.delete_env(:concept, :req_llm_module) end)
      :ok
    end

    test "BUG-045 regression: completes without UndefinedFunctionError",
         %{user_message: msg, user: user} do
      assert {:ok, _} =
               msg
               |> Ash.Changeset.for_update(:respond, %{}, actor: user)
               |> Ash.update()

      # And the agent reply row exists and is complete.
      assert [agent] =
               Ash.read!(Chat.Message, actor: user, authorize?: false)
               |> Enum.filter(&(&1.source == :agent))

      assert agent.complete
      assert agent.text =~ "Hello"
    end

    test "BUG-046: persists prompt_tokens and completion_tokens on the reply",
         %{user_message: msg, user: user} do
      MockReqLLM.set_reply(text: "Hi.", input_tokens: 21, output_tokens: 9)

      {:ok, _} =
        msg
        |> Ash.Changeset.for_update(:respond, %{}, actor: user)
        |> Ash.update()

      [agent] =
        Ash.read!(Chat.Message, actor: user, authorize?: false)
        |> Enum.filter(&(&1.source == :agent))

      assert agent.prompt_tokens == 21
      assert agent.completion_tokens == 9
      assert is_integer(agent.latency_ms) and agent.latency_ms >= 0
    end

    test "BUG-046 extension: persists grounding_score when Google provider_meta is present",
         %{user_message: msg, user: user} do
      MockReqLLM.set_reply(
        text: "Grounded reply.",
        input_tokens: 5,
        output_tokens: 3,
        grounding_confidences: [0.5, 1.0]
      )

      {:ok, _} =
        msg
        |> Ash.Changeset.for_update(:respond, %{}, actor: user)
        |> Ash.update()

      [agent] =
        Ash.read!(Chat.Message, actor: user, authorize?: false)
        |> Enum.filter(&(&1.source == :agent))

      assert_in_delta agent.grounding_score, 0.75, 1.0e-9
    end

    test "FUP-028: second invocation does not re-call the LLM",
         %{user_message: msg, user: user} do
      {:ok, _} =
        msg
        |> Ash.Changeset.for_update(:respond, %{}, actor: user)
        |> Ash.update()

      first_calls = MockReqLLM.call_count()
      assert first_calls >= 1

      # Re-run — should be a no-op since a complete response exists.
      {:ok, _} =
        msg
        |> Ash.Changeset.for_update(:respond, %{}, actor: user)
        |> Ash.update()

      assert MockReqLLM.call_count() == first_calls
    end

    test "FUP-028: partial response is finalized with [response interrupted] suffix",
         %{user_message: msg, user: user} = ctx do
      _partial = upsert_agent_reply!(msg, ctx, text: "I was about to say", complete: false)

      {:ok, _} =
        msg
        |> Ash.Changeset.for_update(:respond, %{}, actor: user)
        |> Ash.update()

      # No LLM call.
      assert MockReqLLM.call_count() == 0

      [agent] =
        Ash.read!(Chat.Message, actor: user, authorize?: false)
        |> Enum.filter(&(&1.source == :agent))

      assert agent.complete
      assert agent.text =~ "I was about to say"
      assert agent.text =~ "[response interrupted]"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Fixtures
  # ──────────────────────────────────────────────────────────────────────

  defp base_fixtures(_context) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "respond-test-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, conversation} =
      Chat.Conversation
      |> Ash.Changeset.for_create(:create, %{}, actor: user)
      |> Ash.create()

    {:ok, user_message} =
      Chat.Message
      |> Ash.Changeset.for_create(
        :create,
        %{text: "What can you do?"},
        actor: user
      )
      |> Ash.Changeset.force_change_attribute(:conversation_id, conversation.id)
      |> Ash.create(authorize?: false)

    %{user: user, conversation: conversation, user_message: user_message}
  end

  defp upsert_agent_reply!(user_message, %{conversation: conv}, opts) do
    Chat.Message
    |> Ash.Changeset.for_create(
      :upsert_response,
      %{
        id: Ash.UUIDv7.generate(),
        response_to_id: user_message.id,
        conversation_id: conv.id,
        text: Keyword.fetch!(opts, :text),
        complete: Keyword.get(opts, :complete, false)
      },
      actor: %AshAi{}
    )
    |> Ash.create!()
  end
end
