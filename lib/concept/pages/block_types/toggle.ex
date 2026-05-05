defmodule Concept.Pages.BlockTypes.Toggle do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :toggle
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{"open" => true}
  @impl true
  def validate_props(%{"open" => o}) when is_boolean(o), do: :ok
  def validate_props(_), do: {:error, "open must be boolean"}
  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu,
    do: %{label: "Toggle", icon: "▸", keywords: ["toggle", "collapse", "fold"], group: :advanced}

  @impl true
  def container?, do: true
end
