defmodule Concept.Objects.ToolProjector do
  @moduledoc """
  Projects per-workspace object types into typed MCP tools.

  The generic spine (`record_create`, `record_transition`, `record_list_for_type`)
  is exposed for free by `Concept.AutoTools`. But an agent dropped into a
  workspace with a `Customer` type should see `create_customer`, not just a
  generic `record_create`. Since object types are *runtime rows*, we cannot
  synthesize these at compile time — we **project** them at request time.

  `project/1` is a pure function over already-loaded schema data
  (`%{object_type, field_defs, workflow_states}`) → a list of `%AshAi.Tool{}`
  that point at the **real** generic `Record` actions but carry a type-specific
  `name`, `description` (built from fields + guard prose), and `_meta` so the
  MCP wrapper can route the call back through the generic action with
  `object_type_id` pinned.

  This is data→data: no codegen, no compiled modules per type. Fully unit
  testable without an LLM or a live MCP server.
  """

  alias Concept.Objects.{Guards, Record}

  @doc """
  Project one object type's schema bundle into typed tools.

  `bundle` is a map with:
    * `:object_type` — `%ObjectType{}` (needs `id`, `key`, `name`)
    * `:field_defs` — `[%FieldDef{}]` (non-relational shape the create tool documents)
    * `:workflow_states` — `[%WorkflowState{}]` (target names for the transition tool)
    * `:transitions` — `[%Transition{}]` (optional; for guard-aware descriptions)
  """
  def project(bundle) do
    type = bundle.object_type
    fields = Map.get(bundle, :field_defs, [])
    states = Map.get(bundle, :workflow_states, [])
    transitions = Map.get(bundle, :transitions, [])

    [
      create_tool(type, fields),
      list_tool(type),
      transition_tool(type, states, transitions)
    ]
  end

  @doc "Project many bundles into a flat tool list."
  def project_all(bundles) when is_list(bundles), do: Enum.flat_map(bundles, &project/1)

  defp create_tool(type, fields) do
    field_doc =
      fields
      |> Enum.reject(&relational?/1)
      |> Enum.map_join(", ", fn f -> "#{f.key} (#{f.field_type}#{req(f)})" end)

    desc =
      "Create a #{type.name}." <>
        if(field_doc == "", do: "", else: " Fields: #{field_doc}.")

    %AshAi.Tool{
      name: :"create_#{type.key}",
      resource: Record,
      action: :create,
      description: desc,
      load: [],
      async: false,
      arguments: [],
      action_parameters: nil,
      _meta: %{"object_type_id" => type.id, "object_type_key" => type.key},
      ui: nil,
      identity: nil,
      domain: Concept.Objects
    }
  end

  defp list_tool(type) do
    %AshAi.Tool{
      name: :"list_#{type.key}",
      resource: Record,
      action: :list_for_type,
      description: "List all #{type.name} records.",
      load: [],
      async: false,
      arguments: [],
      action_parameters: nil,
      _meta: %{"object_type_id" => type.id, "object_type_key" => type.key},
      ui: nil,
      identity: nil,
      domain: Concept.Objects
    }
  end

  defp transition_tool(type, states, transitions) do
    state_names =
      states
      |> Enum.map(fn s -> "#{s.name} (#{s.category})" end)
      |> Enum.join(", ")

    guard_prose = guard_summary(transitions)

    desc =
      "Move a #{type.name} to a new state." <>
        if(state_names == "", do: "", else: " States: #{state_names}.") <>
        guard_prose

    %AshAi.Tool{
      name: :"#{type.key}_transition",
      resource: Record,
      action: :transition,
      description: desc,
      load: [],
      async: false,
      arguments: [],
      action_parameters: nil,
      _meta: %{"object_type_id" => type.id, "object_type_key" => type.key},
      ui: nil,
      identity: nil,
      domain: Concept.Objects
    }
  end

  defp guard_summary([]), do: ""

  defp guard_summary(transitions) do
    phrases =
      transitions
      |> Enum.flat_map(fn t -> Guards.describe_all(t.guards || []) end)
      |> Enum.uniq()

    case phrases do
      [] -> ""
      ps -> " Guards: #{Enum.join(ps, "; ")}."
    end
  end

  defp relational?(%{field_type: ft}), do: Concept.Objects.FieldTypes.relational?(ft)
  defp req(%{required?: true}), do: ", required"
  defp req(_), do: ""
end
