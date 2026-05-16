defmodule ConceptWeb.McpTest do
  use ConceptWeb.ConnCase, async: true

  setup do
    # Create test user
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    # Create a valid API key for the user
    {:ok, api_key_resource} =
      Concept.Accounts.ApiKey
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
      })
      |> Ash.create(authorize?: false)

    # The API key is returned in the metadata during creation
    api_key = api_key_resource.__metadata__.plaintext_api_key

    %{user: user, api_key: api_key}
  end

  describe "MCP endpoints" do
    test "lists registered tools", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      # Should contain authorized tools
      tools = response["result"]["tools"]
      assert is_list(tools)
      assert length(tools) >= 2

      tool_names = Enum.map(tools, & &1["name"])
      assert "search_workspace" in tool_names
      assert "answer_question" in tool_names
    end

    test "rejects requests without API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list"
        })

      assert response(conn, 401)
    end

    test "rejects requests with invalid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_key_12345")
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list"
        })

      assert response(conn, 401)
    end
  end
end
