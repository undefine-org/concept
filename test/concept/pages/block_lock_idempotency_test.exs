defmodule Concept.Pages.BlockLockIdempotencyTest do
  @moduledoc """
  BUG-047 — :release_lock must be idempotent at the resource level.

  When state drifts (cron release, sibling tab, retry), invoking :release_lock
  on an already-:unlocked block must succeed instead of raising
  AshStateMachine.Errors.NoMatchingTransition.
  """
  use Concept.DataCase, async: true

  alias Concept.{Accounts, Pages}

  defp fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "lockidem_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Lock Idem", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{user: user, workspace: workspace, block: block}
  end

  describe "release_lock idempotency" do
    test "releasing an already-unlocked block succeeds and is a no-op" do
      %{user: user, workspace: ws, block: block} = fixtures()

      {:ok, locked} =
        Pages.acquire_lock(block, %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )

      assert {:ok, first_release} =
               Pages.release_lock(locked, actor: user, tenant: ws.id)

      assert first_release.lock_state == :unlocked
      assert first_release.lock_holder_id == nil

      # Second release on a block whose `state` already :unlocked — this is
      # the drift case that used to raise AshStateMachine.Errors.NoMatchingTransition.
      assert {:ok, second_release} =
               Pages.release_lock(first_release, actor: user, tenant: ws.id)

      assert second_release.lock_state == :unlocked
      assert second_release.lock_holder_id == nil
    end

    test "releasing a freshly-created (never-locked) block succeeds" do
      %{user: user, workspace: ws, block: block} = fixtures()

      # block.state defaults to :unlocked from initial_states — this used to
      # raise NoMatchingTransition unconditionally.
      assert {:ok, released} =
               Pages.release_lock(block, actor: user, tenant: ws.id)

      assert released.lock_state == :unlocked
    end

    test "release after a system actor (cron) already cleared the lock succeeds" do
      %{user: user, workspace: ws, block: block} = fixtures()

      {:ok, locked} =
        Pages.acquire_lock(block, %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )

      # Simulate the AshOban release_expired_locks trigger having run.
      {:ok, _system_released} =
        Pages.release_lock(locked, actor: %{system?: true}, tenant: ws.id)

      # User's LV held_locks still says it holds the lock; their blur fires
      # release_lock and must not error.
      assert {:ok, _} = Pages.release_lock(locked, actor: user, tenant: ws.id)
    end
  end
end
