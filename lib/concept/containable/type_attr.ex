defmodule Concept.Containable.TypeAttr do
  @moduledoc """
  Ash attribute type validating a block's `container_type` against the
  `Concept.Containable` registry. Mirrors `Concept.Pages.BlockTypeAttr`: stored
  as a string, surfaced as an atom, rejected when not a registered container
  type. This is what keeps the persisted discriminator from ever drifting from
  `config :concept, :containables`.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :string

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_atom(value), do: validate(value)

  def cast_input(value, _) when is_binary(value) do
    validate(String.to_existing_atom(value))
  rescue
    ArgumentError -> {:error, message: "unknown container type"}
  end

  def cast_input(_, _), do: {:error, message: "invalid container type"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, _) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, message: "unknown stored container type"}
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(atom, _) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  def dump_to_native(_, _), do: :error

  defp validate(type) do
    if type in Concept.Containable.types() do
      {:ok, type}
    else
      {:error, message: "unknown container type #{inspect(type)}"}
    end
  end
end
