defmodule Concept.Pages.BlockTypes.Paragraph do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :paragraph
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def validate_props(props) when props == %{}, do: :ok
  def validate_props(_), do: {:error, "paragraph takes no props"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Text", icon: "Aa", keywords: ["text", "paragraph", "p"], group: :basic}

  @impl Concept.Pages.BlockType
  def placeholder, do: "Type something…"
end
