defmodule Concept.Pages.BlockTypes.Quote do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :quote
  @impl true
  def default_content, do: Concept.Lexical.empty_quote()
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl true
  def lexical_node, do: "quote"
  @impl true
  def slash_menu,
    do: %{
      label: "Quote",
      icon: "❝",
      keywords: ["quote", "blockquote", "citation"],
      group: :advanced
    }

  @impl true
  def container?, do: false
end
