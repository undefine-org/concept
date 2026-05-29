defmodule Concept.Pages.BlockTypes.NumberedListItem do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :numbered_list_item
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "Numbered list",
      icon: "1.",
      keywords: ["number", "list", "ol", "ordered"],
      group: :list
    }

  @impl Concept.Pages.BlockType
  def placeholder, do: "List"
end
