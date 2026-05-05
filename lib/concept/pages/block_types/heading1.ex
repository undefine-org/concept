defmodule Concept.Pages.BlockTypes.Heading1 do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :heading_1
  @impl true
  def default_content, do: Concept.Lexical.empty_heading(1)
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl true
  def lexical_node, do: "heading"
  @impl true
  def slash_menu,
    do: %{label: "Heading 1", icon: "H1", keywords: ["heading", "h1", "title"], group: :basic}

  @impl true
  def container?, do: false
end
