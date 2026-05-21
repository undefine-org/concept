defmodule Concept.Resources.WorkspaceTenantedTest do
  @moduledoc """
  FUP-029 — contract test for the six workspace-tenanted resources.

  Each must:
  1. Declare multitenancy attribute strategy on `:workspace_id` with `global? false`.
  2. Expose a `:workspace_memberships` has_many relationship targeting
     `Concept.Accounts.Membership`.
  3. Carry at least one policy authorizing reads via
     `Concept.Pages.Checks.WorkspaceMember`.

  After the `Concept.Resources.WorkspaceTenanted` hoist these properties
  emerge from a single `use` line; before the hoist they exist inline. The
  test pins the contract so the migration is observable.
  """
  use ExUnit.Case, async: true

  @resources [
    Concept.Pages.Block,
    Concept.Pages.Page,
    Concept.Knowledge.Link,
    Concept.Knowledge.Citation,
    Concept.Knowledge.TokenLedger,
    Concept.Knowledge.IngestionJob
  ]

  for resource <- @resources do
    describe "#{inspect(resource)}" do
      @resource resource

      test "multitenancy uses attribute :workspace_id with global? false" do
        assert Ash.Resource.Info.multitenancy_strategy(@resource) == :attribute
        assert Ash.Resource.Info.multitenancy_attribute(@resource) == :workspace_id
        refute Ash.Resource.Info.multitenancy_global?(@resource)
      end

      test "exposes :workspace_memberships has_many to Memberships" do
        rel = Ash.Resource.Info.relationship(@resource, :workspace_memberships)

        assert rel, "expected :workspace_memberships relationship on #{inspect(@resource)}"
        assert rel.type == :has_many
        assert rel.destination == Concept.Accounts.Membership
        assert rel.no_attributes?
      end

      test "has a read policy gated by Checks.WorkspaceMember" do
        policies = Ash.Policy.Info.policies(@resource)

        assert Enum.any?(policies, fn policy ->
                 Enum.any?(policy.policies, fn check ->
                   check.check_module == Concept.Pages.Checks.WorkspaceMember
                 end)
               end),
               "expected a WorkspaceMember check on #{inspect(@resource)}"
      end
    end
  end
end
