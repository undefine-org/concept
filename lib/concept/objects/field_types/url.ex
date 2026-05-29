defmodule Concept.Objects.FieldTypes.Url do
  @moduledoc "A URL field; validates an http(s) scheme and a host."
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :url

  @impl true
  def label, do: "URL"

  @impl true
  def icon, do: "🔗"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, _config) when is_binary(value) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      :ok
    else
      {:error, "must be a valid http(s) URL"}
    end
  end

  def validate(_value, _config), do: {:error, "must be a URL string"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}
  def cast(value, _config) when is_binary(value), do: {:ok, String.trim(value)}
  def cast(_value, _config), do: {:error, "is not a valid URL"}

  @impl true
  def json_schema(_config), do: %{"type" => "string", "format" => "uri"}

  @impl true
  def render_value(value, _config, assigns) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <%= if is_binary(@value) and @value != "" do %>
      <a
        href={@value}
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm text-blue-600 underline hover:text-blue-800"
      >
        {short(@value)}
      </a>
    <% else %>
      <span class="text-sm text-notion-text-light">—</span>
    <% end %>
    """
  end

  @impl true
  def render_input(field, _config, assigns) do
    assigns = assign(assigns, :field, field)

    ~H"""
    <input
      type="url"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      placeholder="https://…"
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    />
    """
  end

  defp short(url) do
    case URI.parse(url) do
      %URI{host: h, path: p} when is_binary(h) -> h <> (p || "")
      _ -> url
    end
    |> String.slice(0, 40)
  end
end
