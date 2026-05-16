defmodule Concept.Knowledge.Profiles do
  @moduledoc """
  Concrete retrieval+generation profiles for `Concept.Knowledge`.

  Each profile binds a pipeline shape (rewrite / search / rerank / ground)
  to a Gemini model string and an AshAI tool set. Picked per call via
  `profile: :fast | :default | :thorough | :outline | :contradict | :intent`.

  ## Models (May 2026, stable)
  - `google:gemini-2.5-flash-lite` — fast/cheap; control, rewrite, ground, intent classify.
  - `google:gemini-2.5-flash`      — default chat answers.
  - `google:gemini-2.5-pro`        — thorough; multi-hop loop, outline drafting.

  ## Compile-time validation
  Model strings are validated against the Gemini family regex at compile time;
  set `CONCEPT_ALLOW_ANY_LLM=1` to override (dev only).

  ## Future
  FUP-016: promote to a Spark DSL when entity macro-import surface is verified.
  The current shape is intentionally simple — a list of `%Profile{}` structs
  built from declarative kwlists — so the API surface (`list/0`, `get/1`,
  `get!/1`, `to_pipeline_opts/1`, `to_ash_ai_opts/1`) survives the migration.
  """

  alias Concept.Knowledge.Profile

  @gemini_model_regex ~r/^google:(gemini-[\d.]+(-flash|-pro|-flash-lite)?(-preview)?|gemini-embedding-[12])(-[\w.]+)?$/

  @profiles [
    %Profile{
      name: :fast,
      description: "Cheap chat. No rewrite, no rerank, no ground.",
      rewrite?: false,
      search: [mode: :semantic, limit: 6],
      rerank?: false,
      answer: [model: "google:gemini-2.5-flash-lite"],
      ground?: false,
      tools: [:search_workspace]
    },
    %Profile{
      name: :default,
      description: "Standard chat answers.",
      rewrite?: true,
      search: [mode: :hybrid, limit: 10],
      rerank?: false,
      answer: [model: "google:gemini-2.5-flash"],
      ground?: false,
      tools: [:search_workspace, :answer_question]
    },
    %Profile{
      name: :thorough,
      description: "Rewrite + hybrid + rerank + ground.",
      rewrite?: true,
      search: [mode: :hybrid, limit: 12],
      rerank?: true,
      answer: [model: "google:gemini-2.5-pro"],
      ground?: true,
      tools: [:search_workspace, :answer_question, :summarize_page]
    },
    %Profile{
      name: :outline,
      description: "Loop-mode page drafting; substrate for FUP-011.",
      rewrite?: true,
      search: [mode: :hybrid, limit: 20],
      rerank?: true,
      answer: [model: "google:gemini-2.5-pro"],
      ground?: false,
      tools: [:search_workspace, :create_page, :answer_question],
      loop?: true
    },
    %Profile{
      name: :contradict,
      description: "NLI-style entailment checks for FUP-013 drift alerts.",
      rewrite?: true,
      search: [mode: :semantic, limit: 10],
      rerank?: false,
      answer: [model: "google:gemini-2.5-flash-lite"],
      ground?: false,
      tools: []
    },
    %Profile{
      name: :intent,
      description: "Cmd-K classifier (FUP-007). Picks a tool; doesn't answer.",
      rewrite?: false,
      search: [mode: :semantic, limit: 0],
      rerank?: false,
      answer: [model: "google:gemini-2.5-flash-lite"],
      ground?: false,
      tools: [:search_workspace, :create_page, :link_blocks, :answer_question, :summarize_page]
    }
  ]

  for profile <- @profiles do
    unless System.get_env("CONCEPT_ALLOW_ANY_LLM") == "1" or
             Regex.match?(@gemini_model_regex, profile.answer[:model] || "") do
      raise CompileError,
        description:
          "profile #{inspect(profile.name)} model #{inspect(profile.answer[:model])} " <>
            "is not a Gemini-family model. Allowed pattern: " <>
            Regex.source(@gemini_model_regex) <>
            ". Set CONCEPT_ALLOW_ANY_LLM=1 to override (dev only)."
    end
  end

  @doc "List all declared profiles."
  @spec list() :: [Profile.t()]
  def list, do: @profiles

  @doc "Get a profile by name; nil if missing."
  @spec get(atom()) :: Profile.t() | nil
  def get(name) when is_atom(name), do: Enum.find(@profiles, &(&1.name == name))

  @doc "Get a profile by name; raises ArgumentError if missing."
  @spec get!(atom()) :: Profile.t()
  def get!(name) when is_atom(name) do
    get(name) || raise ArgumentError, "unknown profile: #{inspect(name)}"
  end

  @doc "Profile name → Arcana.Pipeline kwlist."
  def to_pipeline_opts(name), do: name |> get!() |> Profile.to_pipeline_opts()

  @doc "Profile name → AshAi.ToolLoop kwlist."
  def to_ash_ai_opts(name), do: name |> get!() |> Profile.to_ash_ai_opts()
end
