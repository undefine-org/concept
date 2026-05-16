defmodule Concept.Pages.BlockTypes do
  @moduledoc """
  Compile-time registry of all `Concept.Pages.BlockType` implementations.
  Add a 15th type by appending to `:concept, :block_types` in `config.exs`.
  """

  @modules Application.compile_env(:concept, :block_types, [])

  defmodule UnknownBlockType do
    defexception [:type]
    def message(%{type: t}), do: "no block type module registered for #{inspect(t)}"
  end

  @doc "All registered BlockType modules in declaration order."
  def all, do: @modules

  @doc "All public-facing block type atoms (excludes :hidden auxiliaries)."
  def all_types, do: Enum.map(@modules, & &1.type())

  @doc "Lookup BlockType module by atom type."
  def lookup(type) do
    Enum.find(@modules, &(&1.type() == type)) || raise UnknownBlockType, type: type
  end

  def lookup_safe(type) do
    case Enum.find(@modules, &(&1.type() == type)) do
      nil -> {:error, :unknown}
      mod -> {:ok, mod}
    end
  end

  @doc """
  Resolve a block type string (from client payload) to a validated atom.
  Returns `{:ok, atom}` on success or `{:error, :unknown_type}` if the
  type is not in the registry.
  """
  def resolve(type_str) when is_binary(type_str) do
    type = String.to_existing_atom(type_str)

    case Enum.find(@modules, &(&1.type() == type)) do
      nil -> {:error, :unknown_type}
      _mod -> {:ok, type}
    end
  rescue
    ArgumentError -> {:error, :unknown_type}
  end

  @doc "Slash-menu items grouped, hiding internal auxiliaries (`group: :hidden`)."
  def slash_menu_items do
    @modules
    |> Enum.map(fn m -> Map.put(m.slash_menu(), :type, m.type()) end)
    |> Enum.reject(&(&1.group == :hidden))
  end
end
