defmodule Concept.Pages.BlockTypes.Columns do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :columns
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props, do: %{"count" => 2, "ratios" => [0.5, 0.5]}
  @impl true
  def validate_props(%{"count" => c, "ratios" => r}) when is_integer(c) and is_list(r) and c > 1,
    do: :ok

  def validate_props(_), do: {:error, "count int>1, ratios list"}
  @impl true
  def lexical_node, do: "columns"
  @impl true
  def slash_menu,
    do: %{label: "Columns", icon: "⫶⫶", keywords: ["columns", "layout", "grid"], group: :advanced}

  @impl true
  def container?, do: true
end
