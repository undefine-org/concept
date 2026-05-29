defmodule Concept.Objects.McpTest do
  @moduledoc """
  Wave 4: projected MCP tools list + execute through the real AshAi tool
  pipeline (no HTTP). Seeds a workspace (Task type present) and adds a custom
  type to prove per-type projection + routing.
  """
  use Concept.DataCase, async: false

  alias Concept.Objects
  alias Concept.Objects.Mcp

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "mcp_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    %{user: user, ws: ws.id}
  end

  test "list_entries includes projected tools for the seeded Task type", ctx do
    entries = Mcp.list_entries(ctx.ws)
    names = Enum.map(entries, & &1["name"])

    assert "create_task" in names
    assert "list_task" in names
    assert "task_transition" in names

    create = Enum.find(entries, &(&1["name"] == "create_task"))
    assert is_map(create["inputSchema"])
    assert create["description"] =~ "Create a Task"
  end

  test "projected tools track a newly created custom object type", ctx do
    {:ok, _type} = Objects.create_object_type("Customer", actor: ctx.user, tenant: ctx.ws)

    names = ctx.ws |> Mcp.list_entries() |> Enum.map(& &1["name"])
    assert "create_customer" in names
    assert "customer_transition" in names
  end

  test "call create_<key> creates a record without supplying object_type_id", ctx do
    context = %{actor: ctx.user, tenant: ctx.ws, context: %{}}

    {:ok, text} =
      Mcp.call(
        "create_task",
        %{"input" => %{"fields" => %{"title" => "From MCP"}}},
        context,
        ctx.ws
      )

    assert is_binary(text)

    {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
    task = Enum.find(types, &(&1.key == "task"))
    {:ok, records} = Objects.list_records(task.id, actor: ctx.user, tenant: ctx.ws)
    assert Enum.any?(records, &(&1.title == "From MCP"))
  end

  test "call returns :not_projected for unknown / generic tool names", ctx do
    context = %{actor: ctx.user, tenant: ctx.ws, context: %{}}
    assert Mcp.call("record_create", %{}, context, ctx.ws) == :not_projected
    assert Mcp.call("nonexistent_tool", %{}, context, ctx.ws) == :not_projected
  end

  test "projected_names is a MapSet of the workspace's typed tool names", ctx do
    names = Mcp.projected_names(ctx.ws)
    assert MapSet.member?(names, "create_task")
    refute MapSet.member?(names, "record_create")
  end
end
