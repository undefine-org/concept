defmodule Concept.Pages.BlockTypes.Toggle do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :toggle
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def default_props, do: %{"open" => true}
  @impl Concept.Pages.BlockType
  def validate_props(%{"open" => o}) when is_boolean(o), do: :ok
  def validate_props(_), do: {:error, "open must be boolean"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Toggle", icon: "▸", keywords: ["toggle", "collapse", "fold"], group: :advanced}

  @impl Concept.Pages.BlockType
  def placeholder, do: "Toggle"

  @impl Concept.Pages.BlockType
  def container?, do: true
end
