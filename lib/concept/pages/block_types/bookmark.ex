defmodule Concept.Pages.BlockTypes.Bookmark do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :bookmark
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props,
    do: %{"url" => "", "title" => nil, "description" => nil, "favicon_url" => nil}

  @impl true
  def validate_props(%{"url" => url}) when is_binary(url), do: :ok
  def validate_props(_), do: {:error, "missing url"}
  @impl true
  def lexical_node, do: "bookmark"
  @impl true
  def slash_menu,
    do: %{label: "Bookmark", icon: "🔗", keywords: ["bookmark", "link", "url"], group: :media}

  @impl true
  def container?, do: false
end
