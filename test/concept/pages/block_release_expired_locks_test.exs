defmodule Concept.Pages.BlockReleaseExpiredLocksTest do
  @moduledoc """
  Regression coverage for the AshOban `:release_expired_locks` cron trigger
  on `Concept.Pages.Block`. The resource is tenant-scoped by `workspace_id`
  with `global? false`, so the scheduler must iterate every workspace under
  a system actor (see BUG-043 / FUP-027). Without the tenancy wiring,
  invoking the scheduler module raises
  `Ash.Error.Invalid — require a tenant`.
  """
  use Concept.DataCase, async: true
  use Oban.Testing, repo: Concept.Repo

  alias Concept.{Accounts, Pages}

  defp fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rel_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Release Locks", workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{user: user, workspace: workspace, page: page, block: block}
  end

  describe "AshOban scheduler tenancy (FUP-027)" do
    test "fans out per workspace and enqueues release for expired-locked blocks" do
      %{user: user, workspace: ws, block: block} = fixtures()

      {:ok, locked} =
        block
        |> Ash.Changeset.for_update(
          :acquire_lock,
          %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )
        |> Ash.update()

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      Concept.Repo.query!(
        "UPDATE blocks SET lock_expires_at = $1 WHERE id = $2",
        [past, Ecto.UUID.dump!(locked.id)]
      )

      assert :ok =
               Concept.Pages.Block.AshOban.Scheduler.ReleaseExpiredLocks.perform(%Oban.Job{
                 args: %{}
               })

      assert_enqueued(
        worker: Concept.Pages.Block.AshOban.Worker.ReleaseExpiredLocks,
        args: %{"primary_key" => %{"id" => locked.id}, "tenant" => ws.id}
      )
    end
  end
end
