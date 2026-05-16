defmodule Concept.Knowledge.Profiles do
  @moduledoc """
  Concrete retrieval+generation profiles for Concept.Knowledge.

  Each profile binds a pipeline shape (rewrite/search/rerank/ground) to a
  Gemini model string and a tool set. Use as `profile: :fast` etc. when
  calling `Knowledge.ask/3` or `AshAi.ToolLoop.stream/2`.

  Models:
  - `gemini-2.5-flash-lite` — fast/cheap; control plane, rewrite, ground.
  - `gemini-2.5-flash`      — default chat answers.
  - `gemini-2.5-pro`        — thorough; multi-hop loop, outline drafting.
  """
  use Concept.Knowledge.ProfileBuilder

  profiles do
    profile :fast do
      description "Cheap chat. No rewrite, no rerank, no ground."
      rewrite false
      search mode: :semantic, limit: 6
      rerank false
      answer model: "google:gemini-2.5-flash-lite"
      ground false
      tools [:search_workspace]
    end

    profile :default do
      description "Standard chat answers."
      rewrite true
      search mode: :hybrid, limit: 10
      rerank false
      answer model: "google:gemini-2.5-flash"
      tools [:search_workspace, :answer_question]
    end

    profile :thorough do
      description "Rewrite + hybrid + rerank + ground."
      rewrite true
      search mode: :hybrid, limit: 12
      rerank true
      answer model: "google:gemini-2.5-pro"
      ground true
      tools [:search_workspace, :answer_question, :summarize_page]
    end

    profile :outline do
      description "Loop-mode page drafting; substrate for FUP-011."
      rewrite true
      search mode: :hybrid, limit: 20
      rerank true
      answer model: "google:gemini-2.5-pro"
      tools [:search_workspace, :create_page, :answer_question]
      loop? true
    end

    profile :contradict do
      description "NLI-style entailment checks for FUP-013 drift alerts."
      rewrite true
      search mode: :semantic, limit: 10
      rerank false
      answer model: "google:gemini-2.5-flash-lite"
    end

    profile :intent do
      description "Cmd-K classifier (FUP-007). Picks a tool; doesn't answer."
      rewrite false
      search mode: :semantic, limit: 0
      rerank false
      answer model: "google:gemini-2.5-flash-lite"
      tools [:search_workspace, :create_page, :link_blocks, :answer_question, :summarize_page]
    end
  end
end
