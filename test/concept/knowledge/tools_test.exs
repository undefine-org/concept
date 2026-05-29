defmodule Concept.Knowledge.ToolsTest do
  @moduledoc """
  Regression suite for `Concept.Knowledge.Tools.answer_question/3` (BUG-057).

  The deprecated `Concept.Knowledge.Ask` returned an async handle and
  broadcast the answer on a PubSub topic no MCP caller subscribed to. The
  replacement must be SYNCHRONOUS: it returns `{:ok, %{answer, sources}}`
  (or `{:error, _}`) in the response body, never a handle.
  """
  use Concept.DataCase, async: false

  alias Concept.Knowledge.Tools
  alias Concept.TestSupport.LLMStub

  @workspace_id Ash.UUID.generate()

  # Dummy api_key satisfies ReqLLM.Keys before the Req.Test stub intercepts HTTP.
  defp llm_opts, do: [api_key: "test-key", req_http_options: LLMStub.req_http_options()]

  describe "answer_question/3 (BUG-057)" do
    test "returns a synchronous {:ok, %{answer, sources}}, not an async handle" do
      # No collection ingested for this workspace -> Search returns {:ok, []};
      # the answer still resolves (ungrounded). The BUG-057 contract is that the
      # result is synchronous with the answer in the body — not an async handle
      # broadcast on an unsubscribed PubSub topic (the old Ask behaviour).
      LLMStub.stub_text("Concept is a workspace tool.")

      assert {:ok, %{answer: answer, sources: sources}} =
               Tools.answer_question("What is Concept?", @workspace_id, llm_opts())

      assert is_binary(answer)
      assert is_list(sources)
    end

    test "propagates an LLM error as {:error, _} (still synchronous)" do
      LLMStub.stub_error(429)

      assert {:error, _reason} =
               Tools.answer_question("anything", @workspace_id, llm_opts())
    end
  end
end
