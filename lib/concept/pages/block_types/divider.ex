defmodule Concept.Pages.BlockTypes.Divider do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :divider
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props, do: %{}
  @impl true
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}
  @impl true
  def lexical_node, do: "divider"
  @impl true
  def slash_menu,
    do: %{label: "Divider", icon: "—", keywords: ["divider", "hr", "line", "rule"], group: :media}

  @impl true
  def container?, do: false
end
