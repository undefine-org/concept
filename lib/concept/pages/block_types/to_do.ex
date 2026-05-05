defmodule Concept.Pages.BlockTypes.ToDo do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :to_do
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{"checked" => false}
  @impl true
  def validate_props(%{"checked" => v}) when is_boolean(v), do: :ok
  def validate_props(_), do: {:error, "checked must be boolean"}
  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu,
    do: %{
      label: "To-do",
      icon: "☐",
      keywords: ["todo", "task", "checkbox", "check"],
      group: :list
    }

  @impl true
  def container?, do: false
end
