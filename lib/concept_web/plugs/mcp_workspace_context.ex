defmodule ConceptWeb.Plugs.MCPWorkspaceContext do
  @moduledoc """
  Resolves the workspace tenant for an MCP request.

  Resolution precedence (must match the contract documented in
  `docs/mcp_parity.md` and AGENTS.md):

    1. If the authenticated ApiKey has a non-nil `workspace_id` →
       that workspace, ignoring any header. Bound keys are stronger
       than per-request hints to avoid privilege confusion.
    2. Else if the request carries an `mcp-workspace-id` header *and*
       the actor is a member of that workspace → that workspace.
    3. Else → no tenant assigned. Workspace-agnostic actions still
       work (e.g. `workspace_for_user`); mutation tools refuse via
       the action's tenancy invariant.

  The resolved tenant is stored under `conn.assigns[:mcp_tenant]`.
  The companion `fetch_tenant/1` MFA is wired into
  `AshAi.Mcp.Router`'s `tenant:` option.
  """

  @behaviour Plug

  import Plug.Conn

  alias Concept.Accounts

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    case resolve(user, conn) do
      {:ok, :none} ->
        assign(conn, :mcp_tenant, nil)

      {:ok, ws_id} ->
        conn
        |> assign(:mcp_tenant, ws_id)
        |> Ash.PlugHelpers.set_tenant(ws_id)

      {:error, reason} ->
        body = Jason.encode!(%{
          error: "workspace_context_invalid",
          reason: to_string(reason),
          hint:
            "Either bind the API key to a workspace at creation, or pass an " <>
              "`mcp-workspace-id` header with a workspace you are a member of."
        })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, body)
        |> halt()
    end
  end

  @doc """
  MFA target for `AshAi.Mcp.Router`'s `tenant:` option.

  Returns the workspace_id assigned by `call/2` or `nil` for
  workspace-agnostic requests.
  """
  def fetch_tenant(conn), do: conn.assigns[:mcp_tenant]

  defp resolve(nil, _conn), do: {:ok, :none}

  defp resolve(user, conn) do
    case bound_workspace_id(user) do
      nil -> resolve_from_header(user, conn)
      ws_id -> {:ok, ws_id}
    end
  end

  defp bound_workspace_id(user) do
    case user do
      %{__metadata__: %{api_key: %{workspace_id: ws_id}}} when not is_nil(ws_id) -> ws_id
      _ -> nil
    end
  end

  defp resolve_from_header(user, conn) do
    case get_req_header(conn, "mcp-workspace-id") do
      [ws_id | _] ->
        case Accounts.get_membership(user.id, ws_id, actor: user) do
          {:ok, %{}} -> {:ok, ws_id}
          {:ok, nil} -> {:error, :not_a_member}
          {:error, _} -> {:error, :membership_check_failed}
        end

      [] ->
        {:ok, :none}
    end
  end
end
