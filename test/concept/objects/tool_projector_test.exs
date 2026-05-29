defmodule Concept.Objects.ToolProjectorTest do
  @moduledoc """
  Wave 4: the ToolProjector is a pure function — typed tools for a workspace's
  object types, derived from schema data, pointing at the generic Record
  actions. No LLM or live MCP server needed.
  """
  use ExUnit.Case, async: true

  alias Concept.Objects.ToolProjector

  defp type(key, name), do: %{id: "t-#{key}", key: key, name: name}

  defp field(key, ft, opts \\ %{}) do
    Map.merge(%{key: key, field_type: ft, required?: false, name: key}, opts)
  end

  defp state(name, cat), do: %{name: name, category: cat}

  test "projects create/list/transition tools named by the type key" do
    bundle = %{
      object_type: type("customer", "Customer"),
      field_defs: [field("arr", :number), field("tier", :select)],
      workflow_states: [state("Lead", :backlog), state("Active", :doing)],
      transitions: []
    }

    tools = ToolProjector.project(bundle)
    names = Enum.map(tools, & &1.name)

    assert :create_customer in names
    assert :list_customer in names
    assert :customer_transition in names
  end

  test "tools point at the real generic Record actions and carry object_type_id meta" do
    bundle = %{
      object_type: type("bug", "Bug"),
      field_defs: [field("title", :text, %{required?: true})],
      workflow_states: [],
      transitions: []
    }

    [create, list, transition] = ToolProjector.project(bundle)

    assert create.resource == Concept.Objects.Record
    assert create.action.name == :create
    assert list.action.name == :list_for_type
    assert transition.action.name == :transition

    for t <- [create, list, transition] do
      assert t._meta["object_type_id"] == "t-bug"
      assert t.domain == Concept.Objects
    end
  end

  test "create description lists non-relational fields with required marker" do
    bundle = %{
      object_type: type("task", "Task"),
      field_defs: [
        field("title", :text, %{required?: true}),
        field("priority", :select),
        field("blocked_by", :relation)
      ],
      workflow_states: [],
      transitions: []
    }

    [create | _] = ToolProjector.project(bundle)
    assert create.description =~ "title (text, required)"
    assert create.description =~ "priority (select)"
    # relation fields are excluded from the create field doc (they go via links)
    refute create.description =~ "blocked_by"
  end

  test "transition description lists state names and guard prose" do
    bundle = %{
      object_type: type("task", "Task"),
      field_defs: [],
      workflow_states: [state("Todo", :todo), state("Done", :done)],
      transitions: [
        %{guards: [%{"kind" => "requires_approval", "config" => %{"by" => "creator"}}]}
      ]
    }

    [_, _, transition] = ToolProjector.project(bundle)
    assert transition.description =~ "Todo (todo)"
    assert transition.description =~ "Done (done)"
    assert transition.description =~ "approval by the creator"
  end

  test "project_all flattens multiple bundles" do
    bundles = [
      %{object_type: type("a", "A"), field_defs: [], workflow_states: [], transitions: []},
      %{object_type: type("b", "B"), field_defs: [], workflow_states: [], transitions: []}
    ]

    tools = ToolProjector.project_all(bundles)
    assert length(tools) == 6
    assert :create_a in Enum.map(tools, & &1.name)
    assert :create_b in Enum.map(tools, & &1.name)
  end
end
