defmodule Concept.Pages.Checks.WorkspaceMemberTest do
  @moduledoc """
  BUG-048 — `Concept.Pages.Checks.WorkspaceMember` was a `SimpleCheck` that
  fired an extra `SELECT … FROM memberships` per policy evaluation. It must
  now be an `Ash.Policy.FilterCheck` so the membership predicate is fused into
  the main action SQL (the `EXISTS` subquery rides on the UPDATE/SELECT,
  no separate roundtrip).

  We assert:
  1. Behavioural parity: members are authorized, non-members are not.
  2. Query plan: invoking an authorized update issues 0 standalone
     `SELECT … FROM memberships` statements (the EXISTS is part of the UPDATE).
  """
  use Concept.DataCase, async: false

  alias Concept.{Accounts, Pages}

  defp setup_member do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wsmem_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("WS check", workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, block} =
      Pages.create_block(:page, page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{user: user, workspace: workspace, page: page, block: block}
  end

  defp setup_outsider do
    {:ok, outsider} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "outsider_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    outsider
  end

  describe "behavioural parity" do
    test "members can read pages in their workspace" do
      %{user: user, workspace: ws, page: page} = setup_member()

      assert {:ok, _} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    end

    test "non-members are forbidden" do
      %{workspace: ws, page: page} = setup_member()
      outsider = setup_outsider()

      assert {:error, _} = Pages.get_page(page.id, actor: outsider, tenant: ws.id)
    end

    test "members can update content on their blocks" do
      %{user: user, workspace: ws, block: block} = setup_member()

      {:ok, locked} =
        Pages.acquire_lock(block, %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )

      assert {:ok, _} =
               Pages.update_content(locked, %{"root" => %{"children" => []}},
                 actor: user,
                 tenant: ws.id
               )
    end
  end

  describe "query plan (no standalone membership roundtrip)" do
    setup do
      pid = self()
      ref = make_ref()

      handler_id = "test-membership-query-counter-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:concept, :repo, :query],
        fn _event, _measurements, metadata, _ ->
          # Capture top-level membership SELECTs only (the EXISTS subquery is
          # part of a different statement that does not appear as a separate
          # `SELECT … FROM memberships AS m0` query).
          if standalone_membership_select?(metadata[:query]) do
            send(pid, {ref, :membership_select, metadata[:query]})
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, ref: ref}
    end

    test "release_lock does not issue a standalone memberships SELECT", %{ref: ref} do
      %{user: user, workspace: ws, block: block} = setup_member()

      {:ok, locked} =
        Pages.acquire_lock(block, %{user_id: user.id, ttl_seconds: 30},
          actor: user,
          tenant: ws.id
        )

      # Drain any setup queries.
      drain_membership_messages(ref)

      assert {:ok, _} = Pages.release_lock(locked, actor: user, tenant: ws.id)

      refute_received {^ref, :membership_select, _}
    end
  end

  defp standalone_membership_select?(nil), do: false

  defp standalone_membership_select?(sql) when is_binary(sql) do
    # A top-level `SELECT … FROM memberships AS m0` — not the EXISTS
    # subquery, which appears as `FROM "blocks" … WHERE EXISTS (SELECT 1 FROM "memberships"…)`.
    String.starts_with?(sql, "SELECT ") and String.contains?(sql, "FROM \"memberships\" AS m0")
  end

  defp drain_membership_messages(ref) do
    receive do
      {^ref, :membership_select, _} -> drain_membership_messages(ref)
    after
      0 -> :ok
    end
  end
end
