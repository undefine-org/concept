defmodule Concept.Pages.BlockTypes.ToDo do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :to_do
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def default_props, do: %{"checked" => false}
  @impl Concept.Pages.BlockType
  def validate_props(%{"checked" => v}) when is_boolean(v), do: :ok
  def validate_props(_), do: {:error, "checked must be boolean"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{
      label: "To-do",
      icon: "☐",
      keywords: ["todo", "task", "checkbox", "check"],
      group: :list
    }

  @impl Concept.Pages.BlockType
  def placeholder, do: "To-do"
end
