defmodule Concept.Pages.BlockTypes.Table do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :table
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props,
    do: %{"rows" => 2, "cols" => 2, "has_header_row" => true, "column_widths" => [200, 200]}

  @impl true
  def validate_props(%{"rows" => r, "cols" => c, "column_widths" => w})
      when is_integer(r) and is_integer(c) and is_list(w) and r > 0 and c > 0, do: :ok

  def validate_props(_), do: {:error, "rows/cols ints; column_widths list"}
  @impl true
  def lexical_node, do: "table"
  @impl true
  def slash_menu, do: %{label: "Table", icon: "▦", keywords: ["table", "grid"], group: :advanced}
  @impl true
  def container?, do: true
end
