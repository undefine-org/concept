defmodule Concept.Pages.BlockTypes.Equation do
  use Concept.Pages.BlockType.Static

  @impl Concept.Pages.BlockType
  def type, do: :equation

  @impl Concept.Pages.BlockType
  def default_content, do: %{}

  @impl Concept.Pages.BlockType
  def container?, do: false

  @impl Concept.Pages.BlockType
  def default_props, do: %{"tex" => ""}

  @impl Concept.Pages.BlockType
  def validate_props(%{"tex" => t}) when is_binary(t), do: :ok
  def validate_props(_), do: {:error, "tex must be string"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "equation"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "Equation",
      icon: "Σ",
      keywords: ["equation", "math", "tex", "latex"],
      group: :media
    }

  # Render contract (informal; see Concept.Pages.BlockType moduledoc).
  def render(assigns) do
    _ = assigns
    ~H'<div class="text-notion-text-light py-2">Equation (KaTeX)</div>'
  end
end
