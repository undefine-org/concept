defmodule Concept.Pages.BlockTypes.Heading3 do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :heading_3
  @impl true
  def default_content, do: Concept.Lexical.empty_heading(3)
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl true
  def lexical_node, do: "heading"
  @impl true
  def slash_menu,
    do: %{label: "Heading 3", icon: "H3", keywords: ["heading", "h3"], group: :basic}

  @impl true
  def container?, do: false
end
