defmodule Concept.Pages.BlockTypeAttr do
  @moduledoc "Ash attribute type validating against BlockTypes registry."
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
      ArgumentError -> {:error, message: "unknown block type"}
    end
  end

  def cast_input(_, _), do: {:error, message: "invalid type"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, _) when is_binary(value) do
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:error, message: "unknown stored block type"}
    end
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(atom, _) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  def dump_to_native(_, _), do: :error

  defp validate(type) do
    if type in Concept.Pages.BlockTypes.all_types() do
      {:ok, type}
    else
      {:error, message: "unknown block type #{inspect(type)}"}
    end
  end
end
