defmodule Concept.Objects.FieldTypes.Number do
  @moduledoc "A numeric field (integer or float)."
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :number

  @impl true
  def label, do: "Number"

  @impl true
  def icon, do: "#"

  @impl true
  def validate(nil, _config), do: :ok
  def validate(value, _config) when is_number(value), do: :ok
  def validate(_value, _config), do: {:error, "must be a number"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}
  def cast(value, _config) when is_number(value), do: {:ok, value}

  def cast(value, _config) when is_binary(value) do
    case Float.parse(value) do
      {f, ""} -> {:ok, normalize(f)}
      _ -> {:error, "is not a valid number"}
    end
  end

  def cast(_value, _config), do: {:error, "is not a valid number"}

  # Keep integral floats as integers for clean JSON round-trips.
  defp normalize(f) do
    if f == Float.round(f) and f == trunc(f), do: trunc(f), else: f
  end

  @impl true
  def json_schema(_config), do: %{"type" => "number"}

  @impl true
  def render_value(value, _config, assigns) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <span class="text-sm tabular-nums text-notion-text">{display(@value)}</span>
    """
  end

  @impl true
  def render_input(field, _config, assigns) do
    assigns = assign(assigns, :field, field)

    ~H"""
    <input
      type="number"
      step="any"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    />
    """
  end

  defp display(v) when is_number(v), do: to_string(v)
  defp display(_), do: "—"
end
