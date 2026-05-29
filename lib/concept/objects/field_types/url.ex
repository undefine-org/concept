defmodule Concept.Objects.FieldTypes.Url do
  @moduledoc "A URL field; validates an http(s) scheme and a host."
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :url

  @impl true
  def label, do: "URL"

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
end
