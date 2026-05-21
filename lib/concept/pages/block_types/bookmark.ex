defmodule Concept.Pages.BlockTypes.Bookmark do
  use Concept.Pages.BlockType.Static

  @impl Concept.Pages.BlockType
  def type, do: :bookmark

  @impl Concept.Pages.BlockType
  def default_props,
    do: %{"url" => "", "title" => nil, "description" => nil, "favicon_url" => nil}

  @impl Concept.Pages.BlockType
  def validate_props(%{"url" => url}) when is_binary(url), do: :ok
  def validate_props(_), do: {:error, "missing url"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "bookmark"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Bookmark", icon: "🔗", keywords: ["bookmark", "link", "url"], group: :media}

  # Render contract (informal; see Concept.Pages.BlockType moduledoc).
  def render(assigns) do
    url = get_in(assigns.block.props, ["url"])

    if is_binary(url) and url != "" do
      assigns = assign(assigns, :url, url)

      ~H"""
      <a href={@url} target="_blank" rel="noopener" class="text-notion-blue underline">{@url}</a>
      """
    else
      ~H'<div class="text-notion-text-light">Bookmark</div>'
    end
  end
end
