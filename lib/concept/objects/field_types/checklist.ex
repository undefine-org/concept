defmodule Concept.Objects.FieldTypes.Checklist do
  @moduledoc """
  A list of `{label, checked}` items, stored in the record's `fields` bag.

  Value shape: `[%{"label" => "Write tests", "checked" => true}, ...]`.
  Powers the `requires_checklist_complete` transition guard.
  """
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :checklist

  @impl true
  def label, do: "Checklist"

  @impl true
  def icon, do: "☑"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(items, _config) when is_list(items) do
    if Enum.all?(items, &valid_item?/1) do
      :ok
    else
      {:error, ~s|each item must be %{"label" => string, "checked" => boolean}|}
    end
  end

  def validate(_value, _config), do: {:error, "must be a list of checklist items"}

  defp valid_item?(%{"label" => l, "checked" => c}) when is_binary(l) and is_boolean(c), do: true
  defp valid_item?(_), do: false

  @impl true
  def default(_config), do: []

  @impl true
  def cast(nil, _config), do: {:ok, []}

  def cast(items, _config) when is_list(items) do
    cast =
      Enum.map(items, fn
        %{"label" => l} = item -> %{"label" => to_string(l), "checked" => !!item["checked"]}
        l when is_binary(l) -> %{"label" => l, "checked" => false}
        other -> other
      end)

    if Enum.all?(cast, &valid_item?/1),
      do: {:ok, cast},
      else: {:error, "invalid checklist items"}
  end

  def cast(_value, _config), do: {:error, "is not a valid checklist"}

  @impl true
  def json_schema(_config) do
    %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "label" => %{"type" => "string"},
          "checked" => %{"type" => "boolean"}
        },
        "required" => ["label", "checked"]
      }
    }
  end

  @doc "True when the checklist value has no unchecked items (empty = complete)."
  def complete?(items) when is_list(items), do: Enum.all?(items, & &1["checked"])
  def complete?(_), do: true

  @impl true
  def render_value(value, _config, assigns) do
    items = if(is_list(value), do: value, else: [])
    done = Enum.count(items, & &1["checked"])

    assigns =
      assigns
      |> assign(:total, length(items))
      |> assign(:done, done)

    ~H"""
    <%= if @total > 0 do %>
      <span class="inline-flex items-center gap-1.5 text-xs text-notion-text-light">
        <span class="h-1.5 w-16 overflow-hidden rounded-full bg-notion-gray">
          <span
            class="block h-full rounded-full bg-green-500"
            style={"width: #{percent(@done, @total)}%"}
          />
        </span>
        {@done}/{@total}
      </span>
    <% else %>
      <span class="text-sm text-notion-text-light">—</span>
    <% end %>
    """
  end

  @impl true
  def render_input(field, _config, assigns) do
    items = if(is_list(field.value), do: field.value, else: [])
    assigns = assigns |> assign(:field, field) |> assign(:items, items)

    ~H"""
    <div class="space-y-1">
      <label :for={{item, idx} <- Enum.with_index(@items)} class="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          name={"#{@field.name}[#{idx}][checked]"}
          checked={item["checked"]}
          class="rounded border-notion-divider"
        />
        <input type="hidden" name={"#{@field.name}[#{idx}][label]"} value={item["label"]} />
        <span class={[item["checked"] && "line-through text-notion-text-light"]}>
          {item["label"]}
        </span>
      </label>
    </div>
    """
  end

  defp percent(_done, 0), do: 0
  defp percent(done, total), do: round(done / total * 100)
end
