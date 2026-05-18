defmodule ConceptWeb.Plugs.MCPWorkspaceContextTest do
  use ConceptWeb.ConnCase, async: true

  alias ConceptWeb.Plugs.MCPWorkspaceContext

  describe "resolve/2 — bound ApiKey beats header" do
    test "tenant comes from api_key.workspace_id when set", %{conn: conn} do
      ws_id = Ash.UUIDv7.generate()
      user = user_with_api_key(workspace_id: ws_id)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("mcp-workspace-id", Ash.UUIDv7.generate())
        |> MCPWorkspaceContext.call([])

      assert conn.assigns.mcp_tenant == ws_id
      assert Ash.PlugHelpers.get_tenant(conn) == ws_id
    end
  end

  describe "resolve/2 — header fallback" do
    setup do
      user = create_user!()
      ws = create_workspace_for!(user)
      %{user: user, workspace: ws}
    end

    test "tenant comes from `mcp-workspace-id` header when user is a member",
         %{conn: conn, user: user, workspace: ws} do
      conn =
        conn
        |> assign(:current_user, user_with_api_key(user: user, workspace_id: nil))
        |> put_req_header("mcp-workspace-id", ws.id)
        |> MCPWorkspaceContext.call([])

      assert conn.assigns.mcp_tenant == ws.id
    end

    test "400 when header points at a workspace the actor is not a member of",
         %{conn: conn, user: user} do
      other_user = create_user!()
      other_ws = create_workspace_for!(other_user)

      conn =
        conn
        |> assign(:current_user, user_with_api_key(user: user, workspace_id: nil))
        |> put_req_header("mcp-workspace-id", other_ws.id)
        |> MCPWorkspaceContext.call([])

      assert conn.status == 400
      assert conn.halted

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "workspace_context_invalid"
      assert body["reason"] == "not_a_member"
    end
  end

  describe "resolve/2 — no api_key.workspace_id, no header" do
    test "leaves :mcp_tenant nil so agnostic actions proceed", %{conn: conn} do
      user = user_with_api_key(workspace_id: nil)

      conn =
        conn
        |> assign(:current_user, user)
        |> MCPWorkspaceContext.call([])

      assert conn.assigns.mcp_tenant == nil
      refute conn.halted
    end

    test "leaves :mcp_tenant nil when there is no actor at all", %{conn: conn} do
      conn = MCPWorkspaceContext.call(conn, [])

      assert conn.assigns.mcp_tenant == nil
      refute conn.halted
    end
  end

  # ─── helpers ───────────────────────────────────────────────────────────────

  defp create_user! do
    email = "user-#{System.unique_integer([:positive])}@test.local"

    Concept.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "verysecret123!",
      password_confirmation: "verysecret123!"
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_workspace_for!(user) do
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      Concept.Accounts.Workspace.create_personal(
        "Personal #{slug}",
        slug,
        "🏠",
        user.id,
        actor: user,
        authorize?: false
      )

    Concept.Accounts.Membership
    |> Ash.Changeset.for_create(:create, %{
      workspace_id: ws.id,
      user_id: user.id,
      role: :owner
    })
    |> Ash.create!(authorize?: false)

    ws
  end

  defp user_with_api_key(opts) do
    user = Keyword.get(opts, :user) || create_user!()
    workspace_id = Keyword.get(opts, :workspace_id)

    api_key = %Concept.Accounts.ApiKey{
      id: Ash.UUIDv7.generate(),
      user_id: user.id,
      workspace_id: workspace_id,
      expires_at: DateTime.add(DateTime.utc_now(), 3600)
    }

    Ash.Resource.set_metadata(user, %{api_key: api_key, using_api_key?: true})
  end
end
