defmodule Concept.Pages.BlockTypes.NumberedListItem do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :numbered_list_item
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu,
    do: %{
      label: "Numbered list",
      icon: "1.",
      keywords: ["number", "list", "ol", "ordered"],
      group: :list
    }

  @impl true
  def container?, do: false
end
