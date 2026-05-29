defmodule Concept.Objects.Guards do
  @moduledoc """
  Compile-time registry of all `Concept.Objects.Guard` implementations.
  Add a guard by appending to `:concept, :record_guards` in `config.exs`.
  """

  @modules Application.compile_env(:concept, :record_guards, [])

  defmodule UnknownGuard do
    defexception [:kind]
    def message(%{kind: k}), do: "no guard module registered for #{inspect(k)}"
  end

  @doc "All registered guard modules in declaration order."
  def all, do: @modules

  @doc "All registered guard kinds."
  def all_kinds, do: Enum.map(@modules, & &1.kind())

  @doc "Lookup a guard module by atom or string kind; `{:ok, mod} | {:error, :unknown}`."
  def lookup(kind) when is_atom(kind) do
    case Enum.find(@modules, &(&1.kind() == kind)) do
      nil -> {:error, :unknown}
      mod -> {:ok, mod}
    end
  end

  def lookup(kind) when is_binary(kind) do
    lookup(String.to_existing_atom(kind))
  rescue
    ArgumentError -> {:error, :unknown}
  end

  @doc "Palette metadata for the workflow editor: `[%{kind, label}]`."
  def palette do
    Enum.map(@modules, fn m -> %{kind: m.kind(), label: m.label()} end)
  end

  @doc """
  Describe a list of composed guard specs (`[%{"kind" => k, "config" => c}]`)
  as human-readable phrases — for UI and MCP tool descriptions. Unknown kinds
  are rendered defensively.
  """
  def describe_all(guards) when is_list(guards) do
    Enum.map(guards, fn spec ->
      kind = spec["kind"] || spec[:kind]
      config = spec["config"] || spec[:config] || %{}

      case lookup(kind) do
        {:ok, mod} -> mod.describe(config)
        _ -> "#{kind} (unknown guard)"
      end
    end)
  end

  def describe_all(_), do: []
end
