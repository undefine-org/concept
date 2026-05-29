defmodule Concept.Pages.BlockTypes.Heading1 do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :heading_1
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_heading(1)
  @impl Concept.Pages.BlockType
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "heading"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Heading 1", icon: "H1", keywords: ["heading", "h1", "title"], group: :basic}

  @impl Concept.Pages.BlockType
  def placeholder, do: "Heading 1"
  @impl Concept.Pages.BlockType
  def editor_class, do: "ora-block h1"
end
