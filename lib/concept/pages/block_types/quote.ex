defmodule Concept.Pages.BlockTypes.Quote do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :quote
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_quote()
  @impl Concept.Pages.BlockType
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "quote"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "Quote",
      icon: "❝",
      keywords: ["quote", "blockquote", "citation"],
      group: :advanced
    }

  @impl Concept.Pages.BlockType
  def placeholder, do: "Quote"
end
