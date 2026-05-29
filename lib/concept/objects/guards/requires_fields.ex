defmodule Concept.Objects.Guards.RequiresFields do
  @moduledoc """
  Blocks a transition unless the listed fields are all present and non-empty.

  `config`: `%{"fields" => ["owner", "due_date"]}`.
  """
  @behaviour Concept.Objects.Guard
  use Phoenix.Component

  @impl true
  def kind, do: :requires_fields

  @impl true
  def label, do: "Requires fields"

  @impl true
  def icon, do: "▤"

  @impl true
  def render_config_form(config, form) do
    assigns = %{form: form, fields: Map.get(config, "fields", [])}

    ~H"""
    <label class="text-xs text-notion-text-light">Required field keys (comma-separated)</label>
    <input
      type="text"
      name={@form[:fields].name}
      value={Enum.join(@fields, ", ")}
      placeholder="e.g. owner, due_date"
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    />
    """
  end

  @impl true
  def check(record, config, _ctx) do
    fields = Map.get(config, "fields", [])
    bag = record.fields || %{}

    missing = Enum.reject(fields, fn f -> present?(Map.get(bag, f)) end)

    case missing do
      [] -> :ok
      ms -> {:error, "missing required field(s): #{Enum.join(ms, ", ")}"}
    end
  end

  @impl true
  def describe(config) do
    "requires fields: #{Enum.join(Map.get(config, "fields", []), ", ")}"
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(_), do: true
end
