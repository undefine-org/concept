defmodule Concept.Pages.BlockTypes.Divider do
  use Concept.Pages.BlockType.Static

  @impl Concept.Pages.BlockType
  def type, do: :divider

  @impl Concept.Pages.BlockType
  def default_props, do: %{}

  @impl Concept.Pages.BlockType
  def validate_props(p) when p == %{}, do: :ok
  def validate_props(_), do: {:error, "no props"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "divider"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Divider", icon: "—", keywords: ["divider", "hr", "line", "rule"], group: :media}

  # Render contract (informal; see Concept.Pages.BlockType moduledoc).
  def render(assigns) do
    _ = assigns
    ~H'<hr class="border-notion-divider my-2" />'
  end
end
