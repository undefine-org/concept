defmodule Concept.Objects.FieldTypes.Checklist do
  @moduledoc """
  A list of `{label, checked}` items, stored in the record's `fields` bag.

  Value shape: `[%{"label" => "Write tests", "checked" => true}, ...]`.
  Powers the `requires_checklist_complete` transition guard.
  """
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :checklist

  @impl true
  def label, do: "Checklist"

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
end
