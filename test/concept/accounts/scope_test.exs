defmodule Concept.Accounts.ScopeTest do
  use Concept.DataCase, async: false

  alias Concept.Accounts
  alias Concept.Accounts.Scope

  describe "for_user/1" do
    test "returns scope with user, nil workspace, nil role" do
      %{user: user} = setup_all_data()

      scope = Scope.for_user(user)

      assert scope.user.id == user.id
      assert scope.workspace == nil
      assert scope.role == nil
      assert scope.system? == false
    end
  end

  describe "for_user/2" do
    test "for_user(nil, _) returns nil" do
      assert Scope.for_user(nil, "anything") == nil
    end

    test "for_user(user, nil) returns user-only scope" do
      %{user: user} = setup_all_data()

      scope = Scope.for_user(user, nil)

      assert scope.user.id == user.id
      assert scope.workspace == nil
      assert scope.role == nil
    end

    test "for_user(user, workspace_id) resolves membership role" do
      %{user: user, ws: ws, membership: membership} = setup_all_data()

      scope = Scope.for_user(user, ws.id)

      assert scope.user.id == user.id
      assert scope.workspace.id == ws.id
      assert scope.role == membership.role
    end

    test "for_user(user, unknown_workspace_id) returns user-only scope (no raise)" do
      %{user: user} = setup_all_data()

      scope = Scope.for_user(user, Ecto.UUID.generate())

      assert scope.user.id == user.id
      assert scope.workspace == nil
      assert scope.role == nil
    end

    test "for_user(user, workspace_id) without being member returns user-only scope" do
      %{user: user} = setup_all_data()

      slug = "other-#{System.unique_integer([:positive])}"

      {:ok, other_ws} =
        Concept.Accounts.Workspace
        |> Ash.Changeset.for_create(:create_personal, %{
          name: "Other WS",
          slug: slug,
          icon_emoji: "🏠",
          owner_id: user.id
        })
        |> Ash.create(authorize?: false)

      scope = Scope.for_user(user, other_ws.id)

      assert scope.user.id == user.id
      assert scope.workspace == nil
      assert scope.role == nil
    end
  end

  # Helper to create test data without repeating setup per describe block
  defp setup_all_data do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "scope#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      Concept.Accounts.Workspace
      |> Ash.Changeset.for_create(:create_personal, %{
        name: "Scope Test WS",
        slug: slug,
        icon_emoji: "🏠",
        owner_id: user.id
      })
      |> Ash.create(authorize?: false)

    {:ok, membership} =
      Concept.Accounts.Membership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: ws.id,
        user_id: user.id,
        role: :owner
      })
      |> Ash.create(authorize?: false)

    %{user: user, ws: ws, membership: membership}
  end
end
