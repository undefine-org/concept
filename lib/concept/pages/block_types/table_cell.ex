defmodule Concept.Pages.BlockTypes.TableCell do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :table_cell
  @impl true
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl true
  def default_props, do: %{"row_index" => 0, "col_index" => 0}
  @impl true
  def validate_props(%{"row_index" => r, "col_index" => c}) when is_integer(r) and is_integer(c),
    do: :ok

  def validate_props(_), do: {:error, "row_index/col_index ints"}
  @impl true
  def lexical_node, do: "paragraph"
  @impl true
  def slash_menu, do: %{label: "(Cell)", icon: "□", keywords: [], group: :hidden}
  @impl true
  def container?, do: false
end
