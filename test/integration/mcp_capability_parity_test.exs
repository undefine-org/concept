defmodule Concept.Integration.MCPCapabilityParityTest do
  @moduledoc """
  M6 — capability parity, not just catalog parity.

  `mcp_parity_test` proves every described action is *exposed* as a tool. This
  test proves a representative mutating tool is actually *invokable* end-to-end
  through the real MCP tenancy path with a member actor — closing the gap that
  let M1 (lock-gated writes) and M3 (tenant) pass the metadata checks while
  being broken in practice.

  It drives the tool the way the MCP stack does:

    1. `MCPWorkspaceContext` resolves the tenant from the `mcp-workspace-id`
       header + membership check.
    2. The registered `block_update_content` tool's resource/action is invoked
       with that tenant and the member actor — **without** any prior
       `acquire_lock` (an LLM has no focus event).
  """
  use Concept.DataCase, async: false
  @moduletag :integration

  alias Concept.{Accounts, Pages}
  alias ConceptWeb.Plugs.MCPWorkspaceContext

  defp setup_member do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cap_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Cap", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    %{user: user, ws: ws, page: page, block: block}
  end

  defp tool!(domain, name) do
    Enum.find(AshAi.Info.tools(domain), &(&1.name == name)) ||
      flunk("tool #{name} is not registered on #{inspect(domain)}")
  end

  test "MCPWorkspaceContext resolves the tenant for a member via header" do
    %{user: user, ws: ws} = setup_member()

    conn =
      Plug.Test.conn(:post, "/mcp")
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_req_header("mcp-workspace-id", ws.id)
      |> MCPWorkspaceContext.call([])

    refute conn.halted
    assert conn.assigns.mcp_tenant == ws.id
    assert MCPWorkspaceContext.fetch_tenant(conn) == ws.id
  end

  test "MCPWorkspaceContext refuses a non-member's header" do
    %{ws: ws} = setup_member()

    {:ok, outsider} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "outsider_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    conn =
      Plug.Test.conn(:post, "/mcp")
      |> Plug.Conn.assign(:current_user, outsider)
      |> Plug.Conn.put_req_header("mcp-workspace-id", ws.id)
      |> MCPWorkspaceContext.call([])

    assert conn.halted
    assert conn.status == 400
  end

  test "block_update_content tool is invokable through the resolved tenant without a pre-lock" do
    %{user: user, ws: ws, block: block} = setup_member()

    # Resolve the tenant exactly as the MCP stack would.
    conn =
      Plug.Test.conn(:post, "/mcp")
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_req_header("mcp-workspace-id", ws.id)
      |> MCPWorkspaceContext.call([])

    tenant = MCPWorkspaceContext.fetch_tenant(conn)
    assert tenant == ws.id

    tool = tool!(Concept.Pages, :block_update_content)

    # Drive the *registered tool's* action — no acquire_lock first.
    assert {:ok, updated} =
             block
             |> Ash.Changeset.for_update(
               tool.action,
               %{content: %{"root" => %{"children" => []}}},
               actor: user,
               tenant: tenant
             )
             |> Ash.update(actor: user, tenant: tenant)

    assert updated.lock_state == :unlocked
  end
end
