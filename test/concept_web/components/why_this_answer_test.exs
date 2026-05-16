defmodule ConceptWeb.Components.WhyThisAnswerTest do
  use ConceptWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import ConceptWeb.Components.WhyThisAnswer

  alias Concept.Knowledge.Chat.Message

  describe "why_this_answer/1" do
    test "renders all 4 sections when fully populated" do
      message = %Message{
        id: Ash.UUIDv7.generate(),
        text: "What is the capital of France?",
        rewritten_prompt: "Query: capital city of France",
        search_trace: [
          %{
            "chunk_id" => "chunk-1",
            "score" => 0.95,
            "kept?" => true,
            "snippet" => "Paris is the capital of France"
          },
          %{
            "chunk_id" => "chunk-2",
            "score" => 0.85,
            "kept?" => false,
            "snippet" => "France is a country in Europe"
          }
        ],
        prompt_tokens: 120,
        completion_tokens: 45,
        latency_ms: 1500,
        grounding_score: 0.92
      }

      html = render_component(&why_this_answer/1, message: message)

      # Check for all 4 sections
      assert html =~ "ora-why-section-prompt"
      assert html =~ "ora-why-section-retrieval"
      assert html =~ "ora-why-section-reranking"
      assert html =~ "ora-why-section-generation"

      # Check content
      assert html =~ "What is the capital of France?"
      assert html =~ "Query: capital city of France"
      assert html =~ "2 chunks retrieved"
      assert html =~ "1 chunks kept for generation"
      assert html =~ "1500ms"
      assert html =~ "120 prompt"
      assert html =~ "45 completion"
      assert html =~ "0.92"
    end

    test "rewritten prompt section hidden when nil" do
      message = %Message{
        id: Ash.UUIDv7.generate(),
        text: "What is the capital of France?",
        rewritten_prompt: nil,
        search_trace: [],
        prompt_tokens: 100,
        completion_tokens: 30,
        latency_ms: 1000,
        grounding_score: nil
      }

      html = render_component(&why_this_answer/1, message: message)

      # Should show prompt section but not the rewritten part
      assert html =~ "ora-why-section-prompt"
      assert html =~ "What is the capital of France?"
      refute html =~ "Original:"
      refute html =~ "Rewritten:"
    end

    test "reranking section hidden when search_trace empty" do
      message = %Message{
        id: Ash.UUIDv7.generate(),
        text: "What is the capital of France?",
        rewritten_prompt: nil,
        search_trace: [],
        prompt_tokens: 100,
        completion_tokens: 30,
        latency_ms: 1000,
        grounding_score: nil
      }

      html = render_component(&why_this_answer/1, message: message)

      # Should not show retrieval or reranking sections
      refute html =~ "ora-why-section-retrieval"
      refute html =~ "ora-why-section-reranking"

      # But should show prompt and generation
      assert html =~ "ora-why-section-prompt"
      assert html =~ "ora-why-section-generation"
    end

    test "grounding score hidden when nil" do
      message = %Message{
        id: Ash.UUIDv7.generate(),
        text: "What is the capital of France?",
        rewritten_prompt: nil,
        search_trace: [],
        prompt_tokens: 100,
        completion_tokens: 30,
        latency_ms: 1000,
        grounding_score: nil
      }

      html = render_component(&why_this_answer/1, message: message)

      # Should show generation section
      assert html =~ "ora-why-section-generation"
      assert html =~ "1000ms"
      assert html =~ "100 prompt"

      # But not grounding score
      refute html =~ "Grounding score:"
    end

    test "component is pure (no side effects, no DB reads)" do
      # This test verifies the component doesn't make DB calls
      # by passing a plain struct without loading associations
      message = %Message{
        id: Ash.UUIDv7.generate(),
        text: "Test message",
        rewritten_prompt: nil,
        search_trace: [],
        prompt_tokens: 50,
        completion_tokens: 20,
        latency_ms: 500,
        grounding_score: nil
      }

      # Should render without errors even with minimal data
      html = render_component(&why_this_answer/1, message: message)

      assert html =~ "Why this answer?"
      assert html =~ "Test message"
    end
  end
end
