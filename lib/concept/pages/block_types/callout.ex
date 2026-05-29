defmodule Concept.Pages.BlockTypes.Callout do
  use Concept.Pages.BlockType.Text

  @colors ~w(default red orange yellow green blue purple pink gray)
  @impl Concept.Pages.BlockType
  def type, do: :callout
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def default_props, do: %{"emoji" => "💡", "color" => "default"}
  @impl Concept.Pages.BlockType
  def validate_props(%{"emoji" => e, "color" => c}) when is_binary(e) and c in @colors, do: :ok

  def validate_props(_),
    do: {:error, "expects emoji string + color one of #{Enum.join(@colors, ",")}"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "Callout",
      icon: "💡",
      keywords: ["callout", "note", "info", "tip"],
      group: :advanced
    }

  @impl Concept.Pages.BlockType
  def placeholder, do: "Callout"

  def colors, do: @colors
end
