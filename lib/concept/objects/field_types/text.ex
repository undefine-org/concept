defmodule Concept.Objects.FieldTypes.Text do
  @moduledoc "A plain string field."
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :text

  @impl true
  def label, do: "Text"

  @impl true
  def validate(nil, _config), do: :ok
  def validate(value, _config) when is_binary(value), do: :ok
  def validate(_value, _config), do: {:error, "must be a string"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}
  def cast(value, _config) when is_binary(value), do: {:ok, value}
  def cast(value, _config), do: {:ok, to_string(value)}

  @impl true
  def json_schema(_config), do: %{"type" => "string"}
end
