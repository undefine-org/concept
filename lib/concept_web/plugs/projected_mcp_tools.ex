defmodule ConceptWeb.Plugs.ProjectedMcpTools do
  @moduledoc """
  Injects per-workspace **projected** object-type tools into the MCP surface.

  AshAi's MCP server resolves `tools/list` and `tools/call` from the
  compile-time DSL only. User-defined object types are runtime rows, so this
  plug augments those two JSON-RPC methods for the resolved tenant:

    * `tools/list` → standard tools (AshAi) ++ projected tools (this app).
    * `tools/call` for a projected name → executed here; everything else is
      passed through untouched to `AshAi.Mcp.Router`.

  Runs after `MCPWorkspaceContext` (tenant resolved) and before the AshAi
  forward. Relies on the `:mcp` pipeline having already parsed the JSON body
  (`Plug.Parsers`), so `conn.params` holds the JSON-RPC envelope and the
  downstream AshAi parser is a no-op (it skips when `body_params` is set).
  """
  import Plug.Conn

  alias Concept.Objects.Mcp

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case {conn.method, conn.params} do
      {"POST", %{"method" => "tools/list", "id" => id}} ->
        handle_list(conn, id)

      {"POST", %{"method" => "tools/call", "id" => id, "params" => params}} ->
        handle_call(conn, id, params)

      _ ->
        conn
    end
  end

  defp tenant(conn), do: Ash.PlugHelpers.get_tenant(conn) || conn.assigns[:mcp_tenant]

  defp handle_list(conn, id) do
    case tenant(conn) do
      nil ->
        conn

      workspace_id ->
        standard = standard_list_entries(conn)
        projected = Mcp.list_entries(workspace_id)

        body =
          json(%{
            "jsonrpc" => "2.0",
            "id" => id,
            "result" => %{"tools" => standard ++ projected}
          })

        send_json(conn, body)
    end
  end

  defp handle_call(conn, id, %{"name" => name} = params) do
    workspace_id = tenant(conn)
    arguments = params["arguments"] || %{}

    context = %{
      actor: Ash.PlugHelpers.get_actor(conn),
      tenant: workspace_id,
      context: Ash.PlugHelpers.get_context(conn) || %{}
    }

    case workspace_id && Mcp.call(name, arguments, context, workspace_id) do
      {:ok, text} ->
        send_json(conn, success(id, text))

      {:error, reason} ->
        send_json(conn, error_result(id, format_error(reason)))

      _ ->
        # :not_projected or no tenant → let AshAi handle it.
        conn
    end
  end

  defp handle_call(conn, _id, _params), do: conn

  defp standard_list_entries(conn) do
    opts = [
      otp_app: :concept,
      tools: true,
      actor: Ash.PlugHelpers.get_actor(conn),
      tenant: tenant(conn)
    ]

    opts
    |> AshAi.Tools.list()
    |> Enum.map(fn req_tool ->
      %{
        "name" => req_tool.name,
        "description" => req_tool.description,
        "inputSchema" => req_tool.parameter_schema
      }
    end)
  end

  defp success(id, text) do
    json(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "isError" => false,
        "content" => [%{"type" => "text", "text" => text}]
      }
    })
  end

  defp error_result(id, message) do
    json(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "isError" => true,
        "content" => [%{"type" => "text", "text" => message}]
      }
    })
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{__struct__: _} = e), do: Exception.message(e)
  defp format_error(other), do: inspect(other)

  defp json(map), do: Jason.encode!(map)

  defp send_json(conn, body) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, body)
    |> halt()
  end
end
