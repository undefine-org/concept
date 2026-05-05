defmodule Concept.Pages.BlockTypes.Equation do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :equation
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props, do: %{"tex" => ""}
  @impl true
  def validate_props(%{"tex" => t}) when is_binary(t), do: :ok
  def validate_props(_), do: {:error, "tex must be string"}
  @impl true
  def lexical_node, do: "equation"
  @impl true
  def slash_menu,
    do: %{
      label: "Equation",
      icon: "Σ",
      keywords: ["equation", "math", "tex", "latex"],
      group: :media
    }

  @impl true
  def container?, do: false
end
