defmodule Concept.Pages.WorkspaceTenantArgTest do
  @moduledoc """
  M3 (MCP parity) — the `workspace_id` create argument must be honest.

  Workspace-tenanted creates derive `workspace_id` from the tenant. The
  redundant `workspace_id` argument was silently ignored, so a caller could
  pass any value (even garbage) and the write would still succeed in the
  tenant's workspace. `AssertWorkspaceMatchesTenant` now rejects a mismatch.
  """
  use Concept.DataCase, async: true

  alias Concept.{Accounts, Pages}

  defp fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wstenant_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Tenant Arg", ws.id, nil, actor: user, tenant: ws.id)
    %{user: user, ws: ws, page: page}
  end

  describe "create_block" do
    test "succeeds when workspace_id arg equals the tenant" do
      %{user: user, ws: ws, page: page} = fixtures()

      assert {:ok, _block} =
               Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    end

    test "rejects a workspace_id arg that differs from the tenant" do
      %{user: user, ws: ws, page: page} = fixtures()

      assert {:error, error} =
               Pages.create_block(page.id, :paragraph, Ash.UUIDv7.generate(), nil,
                 actor: user,
                 tenant: ws.id
               )

      assert Exception.message(error) =~ "workspace_id must match the request tenant"
    end
  end

  describe "create_page" do
    test "succeeds when workspace_id arg equals the tenant" do
      %{user: user, ws: ws} = fixtures()

      assert {:ok, _page} =
               Pages.create_page("Child", ws.id, nil, actor: user, tenant: ws.id)
    end

    test "rejects a workspace_id arg that differs from the tenant" do
      %{user: user, ws: ws} = fixtures()

      assert {:error, error} =
               Pages.create_page("Rogue", Ash.UUIDv7.generate(), nil,
                 actor: user,
                 tenant: ws.id
               )

      assert Exception.message(error) =~ "workspace_id must match the request tenant"
    end
  end
end
