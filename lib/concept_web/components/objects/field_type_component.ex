defmodule ConceptWeb.Objects.FieldTypeComponent do
  @moduledoc """
  Pure dispatcher over the `Concept.Objects.FieldTypes` registry — the
  object-layer analogue of `ConceptWeb.BlockRender`. Routes on a FieldDef's
  `field_type`; never branches per type. Adding a field type makes its
  display, input, and config UI appear everywhere automatically.

  See `docs/objects_and_tasks_ux.md` §1.

  Every function resolves the FieldType module from the registry and delegates
  to its render contract (`render_value/3`, `render_input/3`,
  `render_config_form/2`). Ambient context (`:members` for `:user`,
  `:options` for `:relation`) is forwarded via `assigns`.
  """
  use Phoenix.Component

  alias Concept.Objects.FieldTypes

  @doc """
  Read-only display of a record's value for a field. Required assigns:
  `:field_def` (with `.field_type`, `.config`) and `:value`. Optional:
  `:members`, `:options` (forwarded as context).
  """
  attr :field_def, :map, required: true
  attr :value, :any, default: nil
  attr :members, :list, default: []
  attr :options, :list, default: []

  def value(assigns) do
    mod = mod_for(assigns.field_def)
    config = config_of(assigns.field_def)
    mod.render_value(assigns.value, config, assigns)
  end

  @doc """
  Edit control for a field. Required assigns: `:field_def` and `:field` (a
  `Phoenix.HTML.FormField`). Optional context: `:members`, `:options`.
  """
  attr :field_def, :map, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :members, :list, default: []
  attr :options, :list, default: []

  def input(assigns) do
    mod = mod_for(assigns.field_def)
    config = config_of(assigns.field_def)
    mod.render_input(assigns.field, config, assigns)
  end

  @doc """
  The field's own settings UI in the type editor. Renders nothing when the
  type does not implement `render_config_form/2`. Required assigns:
  `:field_def` and `:form`.
  """
  attr :field_def, :map, required: true
  attr :form, :any, required: true

  def config_form(assigns) do
    mod = mod_for(assigns.field_def)

    if function_exported?(mod, :render_config_form, 2) do
      mod.render_config_form(config_of(assigns.field_def), assigns.form)
    else
      ~H""
    end
  end

  # ── resolution ────────────────────────────────────────────────────────

  defp mod_for(%{field_type: ft}) when is_atom(ft), do: FieldTypes.lookup(ft)

  defp mod_for(%{field_type: ft}) when is_binary(ft) do
    {:ok, key} = FieldTypes.resolve(ft)
    FieldTypes.lookup(key)
  end

  defp config_of(%{config: c}) when is_map(c), do: c
  defp config_of(_), do: %{}
end
