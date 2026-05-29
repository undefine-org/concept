defmodule Concept.Objects.FieldTypes.Relation do
  @moduledoc """
  A reference to one or more other `Record`s. Unlike every other field type,
  relation values are **not** stored in the `Record.fields` JSONB bag — they
  are first-class `RecordLink` rows (so edges are queryable and `blocked_by`
  readiness can be derived in SQL).

  This module validates only the *shape* of an incoming reference: a uuid or a
  list of uuids. The `Record` engine routes persistence to `RecordLink`.

  `config` shape: `%{"target_object_type_id" => uuid, "many" => true}`.

  Render fns expect an ambient `:options` assign — a list of candidate
  `%{id, title}` records of the target type — for the picker. This same
  `render_input/3` is the **seam picker** reused by the `record_ref` block
  (docs/objects_and_tasks_ux.md §4).
  """
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :relation

  @impl true
  def label, do: "Relation"

  @impl true
  def icon, do: "🔗"

  @impl true
  def relational?, do: true

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, config) do
    if many?(config) do
      validate_many(value)
    else
      validate_one(value)
    end
  end

  defp validate_one(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _} -> :ok
      :error -> {:error, "must be a record id (uuid)"}
    end
  end

  defp validate_one(_), do: {:error, "must be a single record id"}

  defp validate_many(value) when is_list(value) do
    if Enum.all?(value, &match?({:ok, _}, Ecto.UUID.cast(&1))),
      do: :ok,
      else: {:error, "must be a list of record ids (uuids)"}
  end

  defp validate_many(_), do: {:error, "must be a list of record ids"}

  @impl true
  def default(config), do: if(many?(config), do: [], else: nil)

  @impl true
  def cast(nil, _config), do: {:ok, nil}

  def cast(value, config) do
    case validate(value, config) do
      :ok -> {:ok, value}
      err -> err
    end
  end

  @impl true
  def json_schema(config) do
    ref = %{"type" => "string", "format" => "uuid"}
    if many?(config), do: %{"type" => "array", "items" => ref}, else: ref
  end

  @impl true
  def render_value(value, _config, assigns) do
    options = Map.get(assigns, :options, [])
    ids = value |> List.wrap() |> Enum.map(&to_string/1)
    linked = Enum.filter(options, fn r -> opt_id(r) in ids end)
    assigns = assign(assigns, :linked, linked)

    ~H"""
    <%= if @linked == [] do %>
      <span class="text-sm text-notion-text-light">—</span>
    <% else %>
      <span class="flex flex-wrap gap-1">
        <span
          :for={r <- @linked}
          class="rounded border border-notion-divider px-1.5 py-0.5 text-xs text-notion-text"
        >
          {opt_title(r)}
        </span>
      </span>
    <% end %>
    """
  end

  @impl true
  def render_input(field, config, assigns) do
    options = Map.get(assigns, :options, [])
    selected = field.value |> List.wrap() |> Enum.map(&to_string/1)

    assigns =
      assigns
      |> assign(:field, field)
      |> assign(:options, options)
      |> assign(:selected, selected)
      |> assign(:many, many?(config))

    ~H"""
    <select
      id={@field.id}
      name={if @many, do: "#{@field.name}[]", else: @field.name}
      multiple={@many}
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    >
      <option :if={!@many} value="">—</option>
      <option :for={r <- @options} value={opt_id(r)} selected={opt_id(r) in @selected}>
        {opt_title(r)}
      </option>
    </select>
    """
  end

  defp many?(config), do: !!Map.get(config, "many", false)

  defp opt_id(%{id: id}), do: to_string(id)
  defp opt_id(%{"id" => id}), do: to_string(id)
  defp opt_id(_), do: ""

  defp opt_title(%{title: t}) when is_binary(t) and t != "", do: t
  defp opt_title(%{"title" => t}) when is_binary(t) and t != "", do: t
  defp opt_title(_), do: "Untitled"
end
