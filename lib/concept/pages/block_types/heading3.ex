defmodule Concept.Pages.BlockTypes.Heading3 do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :heading_3
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_heading(3)
  @impl Concept.Pages.BlockType
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "heading"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Heading 3", icon: "H3", keywords: ["heading", "h3"], group: :basic}

  @impl Concept.Pages.BlockType
  def placeholder, do: "Heading 3"
  @impl Concept.Pages.BlockType
  def editor_class, do: "ora-block h3"
end
