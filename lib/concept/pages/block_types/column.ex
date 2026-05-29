defmodule Concept.Pages.BlockTypes.Column do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :column
  @impl Concept.Pages.BlockType
  def default_props, do: %{"ratio" => 0.5}
  @impl Concept.Pages.BlockType
  def validate_props(%{"ratio" => r}) when is_number(r) and r > 0 and r <= 1, do: :ok
  def validate_props(_), do: {:error, "ratio number 0<r<=1"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "column"
  @impl Concept.Pages.BlockType
  def slash_menu, do: %{label: "(Column)", icon: "▮", keywords: [], group: :hidden}

  @impl Concept.Pages.BlockType
  def container?, do: true
end
