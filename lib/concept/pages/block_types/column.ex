defmodule Concept.Pages.BlockTypes.Column do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :column
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props, do: %{"ratio" => 0.5}
  @impl true
  def validate_props(%{"ratio" => r}) when is_number(r) and r > 0 and r <= 1, do: :ok
  def validate_props(_), do: {:error, "ratio number 0<r<=1"}
  @impl true
  def lexical_node, do: "column"
  @impl true
  def slash_menu, do: %{label: "(Column)", icon: "▮", keywords: [], group: :hidden}
  @impl true
  def container?, do: true
end
