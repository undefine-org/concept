defmodule Concept.Pages.BlockEditableLockTest do
  @moduledoc """
  M1 (MCP parity) — `:update_content` must be self-sufficient.

  The advisory edit lock is a human-collaboration concern. A content write is
  permitted whenever the block is editable by the actor (unlocked, self-held,
  or the foreign lock has expired). Only an *active* foreign lock refuses the
  write. No pre-`acquire_lock` step is required, and a write must not leave a
  dangling lock behind.

  Also pins M2: `acquire_lock`'s `user_id` argument must equal the acting user.
  """
  use Concept.DataCase, async: true

  alias Concept.{Accounts, Pages}

  defp mkuser(tag) do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "editlock_#{tag}_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    user
  end

  defp fixtures do
    owner = mkuser("owner")
    {:ok, [ws]} = Accounts.Workspace.for_user(owner.id, actor: owner)

    {:ok, page} =
      Pages.create_page("Edit Lock", ws.id, nil, actor: owner, tenant: ws.id)

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: owner, tenant: ws.id)

    %{owner: owner, ws: ws, block: block}
  end

  defp add_member(ws, tag) do
    user = mkuser(tag)

    {:ok, _m} =
      Accounts.Membership
      |> Ash.Changeset.for_create(
        :create,
        %{workspace_id: ws.id, user_id: user.id, role: :member},
        authorize?: false
      )
      |> Ash.create(authorize?: false)

    user
  end

  test "writes to an unlocked block without any prior acquire_lock" do
    %{owner: owner, ws: ws, block: block} = fixtures()

    assert block.lock_state == :unlocked

    assert {:ok, updated} =
             Pages.update_content(block, %{"root" => %{"children" => []}},
               actor: owner,
               tenant: ws.id
             )

    # No dangling lock left behind by a one-shot write.
    assert updated.lock_state == :unlocked
    assert updated.lock_holder_id == nil
  end

  test "acquire_lock refuses a user_id that is not the acting user (M2)" do
    %{owner: owner, ws: ws, block: block} = fixtures()
    other = add_member(ws, "spoof")

    assert {:error, error} =
             Pages.acquire_lock(block, %{user_id: other.id, ttl_seconds: 30},
               actor: owner,
               tenant: ws.id
             )

    assert Exception.message(error) =~ "user_id must match the acting user"
  end

  test "refuses a write while another editor holds an active lock" do
    %{owner: owner, ws: ws, block: block} = fixtures()
    other = add_member(ws, "other")

    {:ok, locked} =
      Pages.acquire_lock(block, %{user_id: other.id, ttl_seconds: 30},
        actor: other,
        tenant: ws.id
      )

    assert {:error, error} =
             Pages.update_content(locked, %{"root" => %{"children" => []}},
               actor: owner,
               tenant: ws.id
             )

    assert Exception.message(error) =~ "locked by another editor"
  end

  test "allows a write when a foreign lock has expired" do
    %{owner: owner, ws: ws, block: block} = fixtures()
    other = add_member(ws, "stale")

    # Born expired: a negative ttl makes lock_expires_at land in the past,
    # simulating a holder who vanished before the cron reaped the lock.
    {:ok, stale} =
      Pages.acquire_lock(block, %{user_id: other.id, ttl_seconds: -60},
        actor: other,
        tenant: ws.id
      )

    assert stale.lock_state == :locked
    assert stale.lock_holder_id == other.id

    assert {:ok, _} =
             Pages.update_content(stale, %{"root" => %{"children" => []}},
               actor: owner,
               tenant: ws.id
             )
  end
end
