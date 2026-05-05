defmodule Concept.Pages.BlockTypes.Image do
  @behaviour Concept.Pages.BlockType
  @impl true
  def type, do: :image
  @impl true
  def default_content, do: %{}
  @impl true
  def default_props, do: %{"url" => "", "alt" => "", "aspect_ratio" => nil}
  @impl true
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

  @impl true
  def lexical_node, do: "image"
  @impl true
  def slash_menu,
    do: %{label: "Image", icon: "🖼", keywords: ["image", "picture", "photo"], group: :media}

  @impl true
  def container?, do: false
end
