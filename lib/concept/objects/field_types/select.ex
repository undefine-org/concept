defmodule Concept.Objects.FieldTypes.Select do
  @moduledoc """
  A single-choice field constrained to a configured option set.

  `config` shape: `%{"options" => ["low", "normal", "high"]}`.
  """
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :select

  @impl true
  def label, do: "Select"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, config) when is_binary(value) do
    if value in options(config) do
      :ok
    else
      {:error, "must be one of: #{Enum.join(options(config), ", ")}"}
    end
  end

  def validate(_value, _config), do: {:error, "must be a string option"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}
  def cast(value, _config) when is_binary(value), do: {:ok, value}
  def cast(value, _config), do: {:ok, to_string(value)}

  @impl true
  def json_schema(config) do
    case options(config) do
      [] -> %{"type" => "string"}
      opts -> %{"type" => "string", "enum" => opts}
    end
  end

  defp options(config), do: Map.get(config, "options", [])
end
