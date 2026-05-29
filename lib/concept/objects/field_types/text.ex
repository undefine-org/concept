defmodule Concept.Objects.FieldTypes.Text do
  @moduledoc "A plain string field."
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :text

  @impl true
  def label, do: "Text"

  @impl true
  def icon, do: "✎"

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

  @impl true
  def render_value(value, _config, assigns) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <span class="text-sm text-notion-text">{display(@value)}</span>
    """
  end

  @impl true
  def render_input(field, _config, assigns) do
    assigns = assign(assigns, :field, field)

    ~H"""
    <input
      type="text"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    />
    """
  end

  defp display(v) when is_binary(v) and v != "", do: v
  defp display(_), do: "—"
end
