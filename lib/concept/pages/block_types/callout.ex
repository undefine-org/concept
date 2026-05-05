defmodule Concept.Pages.BlockTypes.Callout do
  @behaviour Concept.Pages.BlockType
  @colors ~w(default red orange yellow green blue purple pink gray)
  @impl true
  def type, do: :callout
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{"emoji" => "💡", "color" => "default"}
  @impl true
  def validate_props(%{"emoji" => e, "color" => c}) when is_binary(e) and c in @colors, do: :ok

  def validate_props(_),
    do: {:error, "expects emoji string + color one of #{Enum.join(@colors, ",")}"}

  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu,
    do: %{
      label: "Callout",
      icon: "💡",
      keywords: ["callout", "note", "info", "tip"],
      group: :advanced
    }

  @impl true
  def container?, do: false

  def colors, do: @colors
end
