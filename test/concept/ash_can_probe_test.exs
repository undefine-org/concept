defmodule Concept.AshCanProbeTest do
  @moduledoc """
  Round-trip test for the **Ash action ↔ permission probe** boundary.

  AshAI's tool-registry builder (`AshAi.Tools.build_tools_and_registry/1`)
  enumerates every action across every configured domain and calls
  `Ash.can?({Resource, action_name, %{}}, actor)` to decide visibility.
  Any cross-attribute validation that doesn't nil-guard its body therefore
  takes the entire `:respond` pipeline down the first time a user submits
  a chat message or evaluates an AI Answer block.

  Concrete example caught in the wild (`Concept.Knowledge.Link`):

      validate fn changeset, _ ->
        source = Concept.Repo.get(Concept.Pages.Block, source_block_id)
        # source_block_id is nil during probe → Repo.get(_, nil) raises
      end

  Fix shape is either:

  * nil-guard the body and short-circuit when ids are absent, or
  * mark the change with `only_when_valid?: true` so Ash skips it during
    probe.

  This test discovers actions reflectively via `Ash.Resource.Info.actions/1`,
  so new resources and new actions are covered automatically with no
  maintenance.
  """
  use Concept.DataCase, async: false

  @domains Application.compile_env!(:concept, :ash_domains)

  # Vendor-owned actions whose changes/validations live in upstream libraries
  # (e.g. `AshAuthentication.TokenResource.RevokeJtiChange`). Those changes
  # are not ours to nil-guard; they are also not exposed to AshAI's tool
  # registry because they require sensitive arguments. Skip explicitly so
  # the probe stays a clean signal for application-owned bugs.
  @vendor_skip MapSet.new([
                 {Concept.Accounts.Token, :revoke_jti},
                 {Concept.Accounts.Token, :revoke_all_stored_for_subject},
                 {Concept.Accounts.Token, :store_token}
               ])

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "can_probe_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, user: user}
  end

  # Build one ExUnit test per (resource, action) pair at compile time.
  # `:read` actions don't make sense to probe with empty input — they accept
  # filters and pagination opts, not attrs — so we skip them. The classes of
  # bug we're catching are validations on mutating actions.
  for domain <- @domains,
      resource <- Ash.Domain.Info.resources(domain),
      %{name: action_name, type: action_type} <- Ash.Resource.Info.actions(resource),
      action_type in [:create, :update, :destroy],
      not MapSet.member?(@vendor_skip, {resource, action_name}) do
    @resource resource
    @action action_name

    test "Ash.can?(#{inspect(resource)}, :#{action_name}, %{}) does not raise",
         %{user: user} do
      # The contract: probing with empty input must return a boolean, never
      # raise. The actual permission result is irrelevant — we only care
      # that the action's validations/changes survive being asked the
      # question with nothing filled in.
      try do
        result = Ash.can?({@resource, @action, %{}}, user, run_queries?: false)
        assert is_boolean(result)
      rescue
        e ->
          flunk("""
          #{inspect(@resource)}.#{@action} crashed during permission probe.

          AshAI calls Ash.can? with empty input for every action when building
          its tool registry. Any validation or change on this action must be
          nil-safe (or use `only_when_valid?: true`).

          See test/concept/knowledge/link_test.exs for an example fix and
          docs/blocks/ADDING_A_BLOCK.md for the broader pattern.

          Exception:
            #{Exception.format(:error, e, __STACKTRACE__)}
          """)
      end
    end
  end
end
