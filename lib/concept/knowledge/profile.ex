defmodule Concept.Knowledge.Profile do
  @moduledoc """
  Compile-time profile struct for retrieval+generation pipelines.

  Profiles bind named configurations to Knowledge.Query resources,
  controlling rewrite, search mode, reranking, grounding, LLM model,
  and tool sets.
  """

  @type search_mode :: :semantic | :hybrid
  @type search_opts :: [mode: search_mode(), limit: non_neg_integer()]
  @type answer_opts :: [model: String.t()]

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t() | nil,
          rewrite?: boolean(),
          search: search_opts(),
          rerank?: boolean(),
          answer: answer_opts(),
          ground?: boolean(),
          tools: [atom()],
          loop?: boolean()
        }

  defstruct [
    :name,
    :description,
    rewrite?: false,
    search: [mode: :hybrid, limit: 10],
    rerank?: false,
    answer: [],
    ground?: false,
    tools: [],
    loop?: false
  ]

  @doc """
  Convert profile to Arcana.Pipeline options.
  """
  @spec to_pipeline_opts(t()) :: keyword()
  def to_pipeline_opts(%__MODULE__{} = profile) do
    [
      search_mode: profile.search[:mode] || :hybrid,
      search_limit: profile.search[:limit] || 10,
      rerank?: profile.rerank?,
      rewrite?: profile.rewrite?,
      ground?: profile.ground?
    ]
  end

  @doc """
  Convert profile to AshAI options.
  """
  @spec to_ash_ai_opts(t()) :: keyword()
  def to_ash_ai_opts(%__MODULE__{} = profile) do
    [
      model: profile.answer[:model],
      tools: profile.tools
    ]
  end
end
