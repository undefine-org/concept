defmodule Concept.Accounts.ScopeTest do
  use Concept.DataCase, async: false

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

  describe "Onboarding reactor (BUG-037 scenario 2)" do
    # Direct invocation of `Concept.Accounts.Reactors.Onboarding` so the
    # `primary?: true` input to `Workspace.:create_personal` is exercised
    # against the persisted attribute (not just the in-memory changeset).
    # If a future refactor drops that input or strips it from `accept`,
    # this is the test that flips red.
    test "sets primary?: true on the created workspace" do
      {:ok, user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "onb#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      # `register_with_password` already runs RunOnboarding once via the
      # after_action change. The reactor is idempotent at the workspace
      # level (different slug timestamp), so we read the workspace it
      # produced rather than re-running it — the assertion under test
      # (`primary?: true`) is on the workspace state, regardless of how
      # many times the reactor fired.
      {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

      assert ws.primary? == true
    end

    # Belt-and-braces: invoke the reactor *directly* (not via the
    # register_with_password after-action) so the test pins the reactor's
    # contract, not the change that wraps it.
    test "Reactor.run/4 directly produces a primary? == true workspace" do
      # User created via a path that bypasses RunOnboarding (manual Ash
      # changeset against the base resource without :register_with_password).
      {:ok, user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "reactor#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      # Wipe what RunOnboarding produced so we can observe a fresh reactor run.
      {:ok, existing} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
      for ws <- existing, do: Ash.destroy!(ws, authorize?: false)

      assert {:ok, ws} =
               Reactor.run(
                 Concept.Accounts.Reactors.Onboarding,
                 %{user: user},
                 %{},
                 async?: false
               )

      reloaded = Ash.get!(Concept.Accounts.Workspace, ws.id, authorize?: false)
      assert reloaded.primary? == true
      assert reloaded.owner_id == user.id
    end
  end

  describe "Concept.Accounts.get_primary_workspace/2 (BUG-037 scenario 3)" do
    # Happy path: the primary? == true workspace wins even if older
    # memberships exist.
    test "returns the workspace flagged primary? == true" do
      %{user: user, ws: primary_ws} = setup_all_data()

      # setup_all_data creates a user via register_with_password which
      # triggers RunOnboarding, leaving a *second* workspace with
      # primary? == true. We must remove it so only our chosen primary
      # remains; otherwise Ash.read_one sees two primary rows.
      {:ok, all_ws} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

      for ws <- all_ws, ws.id != primary_ws.id do
        Ash.destroy!(ws, authorize?: false)
      end

      # Add a second, non-primary membership/workspace to prove
      # primary? wins over recency.
      slug = "secondary-#{System.unique_integer([:positive])}"

      {:ok, secondary_ws} =
        Concept.Accounts.Workspace
        |> Ash.Changeset.for_create(:create_personal, %{
          name: "Secondary WS",
          slug: slug,
          icon_emoji: "📁",
          owner_id: user.id
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        Concept.Accounts.Membership
        |> Ash.Changeset.for_create(:create, %{
          workspace_id: secondary_ws.id,
          user_id: user.id,
          role: :owner
        })
        |> Ash.create(authorize?: false)

      # Flag the chosen workspace as primary.
      primary_ws
      |> Ecto.Changeset.change(primary?: true)
      |> Concept.Repo.update!()

      assert {:ok, ws} = Concept.Accounts.get_primary_workspace(user, actor: user)
      assert ws.id == primary_ws.id
      assert ws.primary? == true
    end

    # Fallback path: when no workspace is flagged primary?, the function
    # must return the OLDEST membership's workspace (sorted by
    # workspace.inserted_at asc). Skipping Onboarding keeps the workspaces
    # un-flagged so we can exercise the fallback branch deterministically.
    test "falls back to the oldest membership when no primary? is marked" do
      {:ok, user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "fb#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      # Wipe RunOnboarding's workspace so both fallback candidates are
      # created here under our control.
      {:ok, existing} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
      for ws <- existing, do: Ash.destroy!(ws, authorize?: false)

      older = create_membership!(user, "older-#{System.unique_integer([:positive])}")
      # Ensure a measurable inserted_at gap so the asc sort is
      # unambiguous on fast machines.
      backdate_workspace!(older, ~U[2026-01-01 00:00:00Z])

      newer = create_membership!(user, "newer-#{System.unique_integer([:positive])}")
      backdate_workspace!(newer, ~U[2026-06-01 00:00:00Z])

      # Belt: neither workspace is marked primary?.
      assert Ash.get!(Concept.Accounts.Workspace, older.id, authorize?: false).primary? == false
      assert Ash.get!(Concept.Accounts.Workspace, newer.id, authorize?: false).primary? == false

      assert {:ok, ws} = Concept.Accounts.get_primary_workspace(user, actor: user)
      assert ws.id == older.id
    end
  end

  defp create_membership!(user, slug) do
    {:ok, ws} =
      Concept.Accounts.Workspace
      |> Ash.Changeset.for_create(:create_personal, %{
        name: "WS #{slug}",
        slug: slug,
        icon_emoji: "🏠",
        owner_id: user.id
      })
      |> Ash.create(authorize?: false)

    {:ok, _} =
      Concept.Accounts.Membership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: ws.id,
        user_id: user.id,
        role: :owner
      })
      |> Ash.create(authorize?: false)

    ws
  end

  defp backdate_workspace!(ws, dt) do
    import Ecto.Query

    Concept.Repo.update_all(
      from(w in "workspaces", where: w.id == type(^ws.id, Ecto.UUID)),
      set: [inserted_at: dt]
    )

    ws
  end
end
