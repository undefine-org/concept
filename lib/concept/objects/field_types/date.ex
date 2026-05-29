defmodule Concept.Objects.FieldTypes.Date do
  @moduledoc "A date field, stored as an ISO-8601 string (`YYYY-MM-DD`)."
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :date

  @impl true
  def label, do: "Date"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, _config) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _} -> :ok
      _ -> {:error, "must be an ISO-8601 date (YYYY-MM-DD)"}
    end
  end

  def validate(_value, _config), do: {:error, "must be a date string"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}

  def cast(%Date{} = d, _config), do: {:ok, Date.to_iso8601(d)}

  def cast(value, _config) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, d} -> {:ok, Date.to_iso8601(d)}
      _ -> {:error, "is not a valid ISO-8601 date"}
    end
  end

  def cast(_value, _config), do: {:error, "is not a valid date"}

  @impl true
  def json_schema(_config), do: %{"type" => "string", "format" => "date"}
end
