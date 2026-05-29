defmodule Concept.Pages.BlockTypes.Columns do
  use Concept.Pages.BlockType.Composite

  @impl Concept.Pages.BlockType
  def type, do: :columns
  @impl Concept.Pages.BlockType
  def composite_layout, do: :columns
  @impl Concept.Pages.BlockType
  def default_props, do: %{"count" => 2, "ratios" => [0.5, 0.5]}
  @impl Concept.Pages.BlockType
  def validate_props(%{"count" => c, "ratios" => r}) when is_integer(c) and is_list(r) and c > 1,
    do: :ok

  def validate_props(_), do: {:error, "count int>1, ratios list"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "columns"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Columns", icon: "⪶⪶", keywords: ["columns", "layout", "grid"], group: :advanced}
end
