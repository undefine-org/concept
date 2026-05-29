defmodule Concept.Objects.Guards.RequiresChecklistComplete do
  @moduledoc """
  Blocks a transition unless a checklist field has all items checked.

  `config`: `%{"field" => "acceptance"}`.
  """
  @behaviour Concept.Objects.Guard
  use Phoenix.Component

  alias Concept.Objects.FieldTypes.Checklist

  @impl true
  def kind, do: :requires_checklist_complete

  @impl true
  def label, do: "Requires checklist complete"

  @impl true
  def icon, do: "☑"

  @impl true
  def render_config_form(config, form) do
    assigns = %{form: form, field: Map.get(config, "field", "")}

    ~H"""
    <label class="text-xs text-notion-text-light">Checklist field key</label>
    <input
      type="text"
      name={@form[:field].name}
      value={@field}
      placeholder="e.g. acceptance"
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    />
    """
  end

  @impl true
  def check(record, config, _ctx) do
    field = Map.get(config, "field")

    cond do
      is_nil(field) ->
        {:error, "requires_checklist_complete guard misconfigured: no field"}

      Checklist.complete?(Map.get(record.fields || %{}, field)) ->
        :ok

      true ->
        {:error, "checklist '#{field}' must be complete"}
    end
  end

  @impl true
  def describe(config) do
    "requires checklist '#{Map.get(config, "field", "?")}' complete"
  end
end
