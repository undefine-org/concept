defmodule Concept.Objects.FieldTypes do
  @moduledoc """
  Compile-time registry of all `Concept.Objects.FieldType` implementations.
  Add a field type by appending to `:concept, :field_types` in `config.exs`.

  Mirrors `Concept.Pages.BlockTypes`: the registry is the single source of
  truth and the `FieldDef`/`Record` resources route to type modules by key.
  """

  @modules Application.compile_env(:concept, :field_types, [])

  defmodule UnknownFieldType do
    defexception [:key]
    def message(%{key: k}), do: "no field type module registered for #{inspect(k)}"
  end

  @doc "All registered FieldType modules in declaration order."
  def all, do: @modules

  @doc "All registered field-type keys."
  def all_keys, do: Enum.map(@modules, & &1.key())

  @doc "Lookup FieldType module by atom key; raises if unknown."
  def lookup(key) do
    Enum.find(@modules, &(&1.key() == key)) || raise UnknownFieldType, key: key
  end

  @doc "Lookup FieldType module by atom key; `{:ok, mod} | {:error, :unknown}`."
  def lookup_safe(key) do
    case Enum.find(@modules, &(&1.key() == key)) do
      nil -> {:error, :unknown}
      mod -> {:ok, mod}
    end
  end

  @doc """
  Resolve a field-type string (from client/MCP payload) to a validated atom.
  Returns `{:ok, atom}` or `{:error, :unknown_type}`.
  """
  def resolve(key_str) when is_binary(key_str) do
    key = String.to_existing_atom(key_str)

    case Enum.find(@modules, &(&1.key() == key)) do
      nil -> {:error, :unknown_type}
      _mod -> {:ok, key}
    end
  rescue
    ArgumentError -> {:error, :unknown_type}
  end

  @doc "True if the given key is a relational field type (values in RecordLink)."
  def relational?(key) do
    case lookup_safe(key) do
      {:ok, mod} -> function_exported?(mod, :relational?, 0) and mod.relational?()
      _ -> false
    end
  end
end
