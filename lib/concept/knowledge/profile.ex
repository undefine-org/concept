defmodule Concept.Knowledge.Profile do
  @moduledoc """
  Retrieval+generation profile struct.

  Built declaratively in `Concept.Knowledge.Profiles`. Bound to Knowledge
  resources via a `:profile` atom attribute; resolved per call via
  `Concept.Knowledge.Profiles.get!/1`.

  ## Fields
  - `:name` — profile atom (`:fast`, `:default`, `:thorough`, ...)
  - `:description` — human-readable summary
  - `:rewrite?` — run a pre-retrieval rewrite step?
  - `:search` — `[mode: :semantic | :hybrid, limit: integer]`
  - `:rerank?` — apply cross-encoder reranking?
  - `:answer` — `[model: "google:..."]`
  - `:ground?` — apply NLI-style grounding check?
  - `:tools` — list of tool atoms exposed to the LLM via AshAI
  - `:loop?` — invoke `AshAi.ToolLoop` (true) or single-shot prompt (false)
  """

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          rewrite?: boolean(),
          search: keyword(),
          rerank?: boolean(),
          answer: keyword(),
          ground?: boolean(),
          tools: [atom()],
          loop?: boolean()
        }

  defstruct [
    :name,
    description: "",
    rewrite?: false,
    search: [mode: :hybrid, limit: 10],
    rerank?: false,
    answer: [],
    ground?: false,
    tools: [],
    loop?: false
  ]

  @doc "Convert profile to Arcana.Pipeline option kwlist."
  @spec to_pipeline_opts(t()) :: keyword()
  def to_pipeline_opts(%__MODULE__{} = profile) do
    [
      search_mode: profile.search[:mode] || :hybrid,
      search_limit: profile.search[:limit] || 10,
      rewrite?: profile.rewrite?,
      rerank?: profile.rerank?,
      ground?: profile.ground?
    ]
  end

  @doc "Convert profile to AshAi.ToolLoop option kwlist."
  @spec to_ash_ai_opts(t()) :: keyword()
  def to_ash_ai_opts(%__MODULE__{} = profile) do
    [
      model: profile.answer[:model],
      tools: profile.tools
    ]
  end
end
