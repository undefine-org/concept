defmodule ConceptWeb.ProjectedMcpToolsTest do
  @moduledoc """
  Wave 4 HTTP path: projected per-type tools appear in `tools/list` and execute
  via `tools/call` over the real /mcp endpoint, tenant-resolved by a
  workspace-bound API key.
  """
  use ConceptWeb.ConnCase, async: false

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "pmcp_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    # workspace-bound key → tenant resolves without a header
    {:ok, key} =
      Concept.Accounts.ApiKey
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        workspace_id: ws.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
      })
      |> Ash.create(authorize?: false)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{key.__metadata__.plaintext_api_key}")
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, ws: ws.id}
  end

  defp rpc(conn, method, params \\ %{}) do
    body = Map.merge(%{"jsonrpc" => "2.0", "id" => 1, "method" => method}, params)
    conn |> post("/mcp", body) |> json_response(200)
  end

  test "tools/list includes both generic spine and projected typed tools", %{conn: conn} do
    resp = rpc(conn, "tools/list")
    names = resp["result"]["tools"] |> Enum.map(& &1["name"])

    # generic spine (AutoTools)
    assert "record_create" in names
    # projected typed tool for the seeded Task type
    assert "create_task" in names
    assert "task_transition" in names
  end

  test "tools/call create_task creates a record", %{conn: conn, user: user, ws: ws} do
    resp =
      rpc(conn, "tools/call", %{
        "params" => %{
          "name" => "create_task",
          "arguments" => %{"input" => %{"fields" => %{"title" => "Via HTTP"}}}
        }
      })

    assert resp["result"], "no result in resp: #{inspect(resp)}"
    refute resp["result"]["isError"], "isError in resp: #{inspect(resp)}"

    text = get_in(resp, ["result", "content", Access.at(0), "text"]) || ""
    assert text =~ "Via HTTP", "created record not in response: #{inspect(resp)}"

    {:ok, types} = Objects.list_object_types(actor: user, tenant: ws)
    task = Enum.find(types, &(&1.key == "task"))
    {:ok, records} = Objects.list_records(task.id, actor: user, tenant: ws)
    assert Enum.any?(records, &(&1.title == "Via HTTP"))
  end

  test "tools/call task_transition moves a record by state name", %{
    conn: conn,
    user: user,
    ws: ws
  } do
    {:ok, types} = Objects.list_object_types(actor: user, tenant: ws)
    task = Enum.find(types, &(&1.key == "task"))

    {:ok, rec} =
      Objects.create_record(task.id, %{fields: %{"title" => "Move me"}}, actor: user, tenant: ws)

    resp =
      rpc(conn, "tools/call", %{
        "params" => %{
          "name" => "task_transition",
          "arguments" => %{"id" => rec.id, "input" => %{"to" => "Todo"}}
        }
      })

    assert resp["result"], "no result in resp: #{inspect(resp)}"
    refute resp["result"]["isError"], "isError in resp: #{inspect(resp)}"

    {:ok, moved} = Objects.get_record(rec.id, actor: user, tenant: ws)
    {:ok, states} = Objects.list_workflow_states(task.workflow_id, actor: user, tenant: ws)
    todo = Enum.find(states, &(&1.name == "Todo"))
    assert moved.state_id == todo.id
  end

  test "a custom object type immediately yields a typed create tool", %{
    conn: conn,
    user: user,
    ws: ws
  } do
    {:ok, _} = Objects.create_object_type("Customer", actor: user, tenant: ws)

    resp = rpc(conn, "tools/list")
    names = resp["result"]["tools"] |> Enum.map(& &1["name"])
    assert "create_customer" in names
  end
end
