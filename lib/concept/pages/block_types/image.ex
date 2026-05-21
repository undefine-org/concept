defmodule Concept.Pages.BlockTypes.Image do
  use Concept.Pages.BlockType.Static

  @impl Concept.Pages.BlockType
  def type, do: :image

  @impl Concept.Pages.BlockType
  def default_props, do: %{"url" => "", "alt" => "", "aspect_ratio" => nil}

  @impl Concept.Pages.BlockType
  def validate_props(%{"url" => url} = p) when is_binary(url) do
    if url == "" or String.starts_with?(url, ["http://", "https://"]) do
      :ok
    else
      {:error, "url must start with http(s):// or be empty"}
    end
    |> case do
      :ok -> alt_ok?(p)
      err -> err
    end
  end

  def validate_props(_), do: {:error, "missing url"}

  defp alt_ok?(%{"alt" => a}) when is_binary(a), do: :ok
  defp alt_ok?(_), do: {:error, "alt must be string"}

  @impl Concept.Pages.BlockType
  def lexical_node, do: "image"

  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Image", icon: "🖼", keywords: ["image", "picture", "photo"], group: :media}

  # Render contract (informal; see Concept.Pages.BlockType moduledoc).
  def render(assigns) do
    url = get_in(assigns.block.props, ["url"])

    if is_binary(url) and url != "" do
      assigns = assign(assigns, :url, url)
      ~H'<img src={@url} class="max-w-full rounded" />'
    else
      ~H'<div class="text-notion-text-light">Image</div>'
    end
  end
end
