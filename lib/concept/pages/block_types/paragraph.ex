defmodule Concept.Pages.BlockTypes.Paragraph do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :paragraph
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(props) when props == %{}, do: :ok
  def validate_props(_), do: {:error, "paragraph takes no props"}
  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu,
    do: %{label: "Text", icon: "Aa", keywords: ["text", "paragraph", "p"], group: :basic}

  @impl true
  def container?, do: false
end
