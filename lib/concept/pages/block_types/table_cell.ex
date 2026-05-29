defmodule Concept.Pages.BlockTypes.TableCell do
  use Concept.Pages.BlockType.Text

  @impl Concept.Pages.BlockType
  def type, do: :table_cell
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_paragraph()
  @impl Concept.Pages.BlockType
  def default_props, do: %{"row_index" => 0, "col_index" => 0}
  @impl Concept.Pages.BlockType
  def validate_props(%{"row_index" => r, "col_index" => c}) when is_integer(r) and is_integer(c),
    do: :ok

  def validate_props(_), do: {:error, "row_index/col_index ints"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "paragraph"
  @impl Concept.Pages.BlockType
  def slash_menu, do: %{label: "(Cell)", icon: "□", keywords: [], group: :hidden}
end
