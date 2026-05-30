defmodule Concept.Accounts.MembersTest do
  @moduledoc """
  Tests for workspace member management and API-key lifecycle.

  Fixtures follow the pattern in `work_view_test.exs`:
  register_with_password → Workspace.for_user.
  """
  use Concept.DataCase, async: true

  alias Concept.Accounts

  defp register_user(email_suffix) do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "member_#{System.unique_integer([:positive])}@#{email_suffix}",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    user
  end

  describe "add_member/3" do
    setup do
      owner = register_user("example.com")
      {:ok, [workspace]} = Accounts.Workspace.for_user(owner.id, actor: owner)
      %{owner: owner, workspace: workspace}
    end

    test "adds an existing user by email", %{owner: owner, workspace: ws} do
      other = register_user("example.com")

      assert {:ok, membership} = Accounts.add_member(ws.id, other.email, actor: owner)
      assert membership.user_id == other.id
      assert membership.workspace_id == ws.id
      assert membership.role == :member
    end

    test "returns :user_not_found for unknown email", %{owner: owner, workspace: ws} do
      assert {:error, :user_not_found} =
               Accounts.add_member(ws.id, "nobody@example.com", actor: owner)
    end

    test "returns :already_member when user is already a member", %{
      owner: owner,
      workspace: ws
    } do
      other = register_user("example.com")

      assert {:ok, _} = Accounts.add_member(ws.id, other.email, actor: owner)
      assert {:error, :already_member} = Accounts.add_member(ws.id, other.email, actor: owner)
    end
  end

  describe "set_member_role/3" do
    setup do
      owner = register_user("example.com")
      {:ok, [workspace]} = Accounts.Workspace.for_user(owner.id, actor: owner)
      other = register_user("example.com")
      {:ok, membership} = Accounts.add_member(workspace.id, other.email, actor: owner)
      %{owner: owner, workspace: workspace, other: other, membership: membership}
    end

    test "sets role to :agent", %{owner: owner, membership: membership} do
      assert {:ok, updated} = Accounts.set_member_role(membership, :agent, actor: owner)
      assert updated.role == :agent
    end

    test "rejects unknown roles", %{owner: owner, membership: membership} do
      assert {:error, _} = Accounts.set_member_role(membership, :superuser, actor: owner)
    end

    test "admin actor CANNOT change an owner's role", %{
      owner: owner,
      workspace: workspace
    } do
      admin = register_user("example.com")
      {:ok, admin_membership} = Accounts.add_member(workspace.id, admin.email, actor: owner)
      {:ok, admin_membership} = Accounts.set_member_role(admin_membership, :admin, actor: owner)

      {:ok, owner_membership} = Accounts.get_membership(owner.id, workspace.id, actor: owner)
      assert {:error, _} = Accounts.set_member_role(owner_membership, :admin, actor: admin)
    end

    test "rejects demoting the last owner", %{owner: owner, workspace: workspace} do
      {:ok, owner_membership} = Accounts.get_membership(owner.id, workspace.id, actor: owner)
      assert {:error, _} = Accounts.set_member_role(owner_membership, :member, actor: owner)
    end

    test "allows demoting an owner when a second owner exists", %{
      owner: owner,
      workspace: workspace
    } do
      other_owner = register_user("example.com")
      {:ok, other_membership} = Accounts.add_member(workspace.id, other_owner.email, actor: owner)
      {:ok, other_membership} = Accounts.set_member_role(other_membership, :owner, actor: owner)

      {:ok, owner_membership} = Accounts.get_membership(owner.id, workspace.id, actor: owner)
      assert {:ok, updated} = Accounts.set_member_role(owner_membership, :member, actor: owner)
      assert updated.role == :member
    end
  end

  describe "list_members/2" do
    setup do
      owner = register_user("example.com")
      {:ok, [workspace]} = Accounts.Workspace.for_user(owner.id, actor: owner)
      other = register_user("example.com")
      {:ok, _} = Accounts.add_member(workspace.id, other.email, actor: owner)
      %{owner: owner, workspace: workspace, other: other}
    end

    test "returns owner and added member with user loaded", %{
      owner: owner,
      workspace: ws,
      other: other
    } do
      assert {:ok, members} = Accounts.list_members(ws.id, actor: owner)
      member_ids = Enum.map(members, & &1.user_id)
      assert owner.id in member_ids
      assert other.id in member_ids

      member = Enum.find(members, &(&1.user_id == other.id))
      assert member.user.email == other.email
      assert member.role == :member
    end
  end

  describe "API key lifecycle" do
    setup do
      owner = register_user("example.com")
      {:ok, [workspace]} = Accounts.Workspace.for_user(owner.id, actor: owner)
      %{owner: owner, workspace: workspace}
    end

    test "issue_api_key returns plaintext once and binds to workspace", %{
      owner: owner,
      workspace: ws
    } do
      assert {:ok, %{api_key: key, plaintext: plaintext}} =
               Accounts.issue_api_key(ws.id, %{}, actor: owner)

      assert is_binary(plaintext)
      assert String.starts_with?(plaintext, "concept_")
      assert key.workspace_id == ws.id
      assert key.user_id == owner.id
    end

    test "list_api_keys shows the key without leaking plaintext", %{
      owner: owner,
      workspace: ws
    } do
      assert {:ok, %{api_key: key, plaintext: _}} =
               Accounts.issue_api_key(ws.id, %{}, actor: owner)

      assert {:ok, keys} = Accounts.list_api_keys(ws.id, actor: owner)
      assert length(keys) == 1
      listed = hd(keys)
      assert listed.id == key.id
      assert listed.workspace_id == ws.id
      # Plaintext must NOT appear in listing
      assert not Map.has_key?(listed.__metadata__, :plaintext_api_key)
    end

    test "revoke_api_key removes the key from the list", %{
      owner: owner,
      workspace: ws
    } do
      assert {:ok, %{api_key: key}} = Accounts.issue_api_key(ws.id, %{}, actor: owner)

      assert {:ok, keys_before} = Accounts.list_api_keys(ws.id, actor: owner)
      assert length(keys_before) == 1

      assert :ok = Accounts.revoke_api_key(key, actor: owner)

      assert {:ok, keys_after} = Accounts.list_api_keys(ws.id, actor: owner)
      assert keys_after == []
    end
  end
end
