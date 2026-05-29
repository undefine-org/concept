defmodule Concept.Objects.FieldTypeAttr do
  @moduledoc "Ash attribute type validating a field-type key against the FieldTypes registry."
  use Ash.Type

  @impl true
  def storage_type(_), do: :string

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_atom(value), do: validate(value)

  def cast_input(value, _) when is_binary(value) do
    try do
      validate(String.to_existing_atom(value))
    rescue
      ArgumentError -> {:error, message: "unknown field type"}
    end
  end

  def cast_input(_, _), do: {:error, message: "invalid field type"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, _) when is_binary(value) do
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:error, message: "unknown stored field type"}
    end
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(atom, _) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  def dump_to_native(_, _), do: :error

  defp validate(key) do
    if key in Concept.Objects.FieldTypes.all_keys() do
      {:ok, key}
    else
      {:error, message: "unknown field type #{inspect(key)}"}
    end
  end
end
