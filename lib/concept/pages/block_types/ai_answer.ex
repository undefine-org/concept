defmodule Concept.Pages.BlockTypes.AiAnswer do
  @moduledoc """
  AI Answer block type — embeds RAG-powered answers inside Concept pages.
  Cached answer in content; refresh button re-runs scoped pipeline.
  """
  @behaviour Concept.Pages.BlockType

  @scopes ~w(subtree page workspace)

  @impl true
  def type, do: :ai_answer

  @impl true
  def default_content, do: %{}

  @impl true
  def default_props, do: %{"prompt" => "", "scope" => "subtree", "model" => nil}

  @impl true
  def validate_props(%{"scope" => s} = props) when s in @scopes,
    do: validate_prompt(props)

  def validate_props(_), do: {:error, "scope must be one of #{Enum.join(@scopes, ",")}"}

  defp validate_prompt(%{"prompt" => p}) when is_binary(p), do: :ok
  defp validate_prompt(_), do: {:error, "prompt must be a string"}

  @impl true
  def lexical_node, do: "ai-answer"

  @impl true
  def slash_menu,
    do: %{label: "AI Answer", icon: "✨", keywords: ~w(ai answer ask), group: :ai}

  @impl true
  def container?, do: false

  @impl true
  def render_static(_block),
    do: "<div class=\"ai-answer-block\"><em>AI Answer</em></div>"
end
