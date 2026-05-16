defmodule Concept.Knowledge.Workers.AggregateTokensTest do
  use Concept.DataCase, async: false
  require Ash.Query

  alias Concept.Knowledge.TokenAccumulator
  alias Concept.Knowledge.TokenLedger
  alias Concept.Knowledge.Workers.AggregateTokens
  alias Concept.Knowledge.SystemActor

  setup do
    # ETS table is shared across tests; clear between runs to avoid leakage.
    :ets.delete_all_objects(:knowledge_token_accumulator)
    :ok
  end

  describe "TokenAccumulator" do
    test "handles telemetry event and updates ETS" do
      workspace_id = Ecto.UUID.generate()
      day = Date.utc_today() |> Date.to_iso8601()

      # Emit a telemetry event
      :telemetry.execute(
        [:concept, :knowledge, :search, :stop],
        %{prompt_tokens: 100, completion_tokens: 50},
        %{workspace_id: workspace_id}
      )

      # Check ETS table
      entries = TokenAccumulator.flush()

      entry =
        Enum.find(entries, fn {{ws_id, _day}, _p, _c, _e, _cnt} -> ws_id == workspace_id end)

      assert entry != nil
      {{^workspace_id, ^day}, prompt, completion, embed, count} = entry
      assert prompt == 100
      assert completion == 50
      assert embed == 0
      assert count == 1

      # Clear for next test
      TokenAccumulator.clear()
    end

    test "accumulates multiple events for same workspace + day" do
      workspace_id = Ecto.UUID.generate()
      day = Date.utc_today() |> Date.to_iso8601()

      # Emit multiple events
      :telemetry.execute(
        [:concept, :knowledge, :search, :stop],
        %{prompt_tokens: 100, completion_tokens: 50},
        %{workspace_id: workspace_id}
      )

      :telemetry.execute(
        [:concept, :knowledge, :embedder, :gemini, :stop],
        %{embed_tokens: 200},
        %{workspace_id: workspace_id}
      )

      :telemetry.execute(
        [:concept, :knowledge, :search, :stop],
        %{prompt_tokens: 75, completion_tokens: 25},
        %{workspace_id: workspace_id}
      )

      # Check accumulated totals
      entries = TokenAccumulator.flush()

      entry =
        Enum.find(entries, fn {{ws_id, _day}, _p, _c, _e, _cnt} -> ws_id == workspace_id end)

      assert entry != nil
      {{^workspace_id, ^day}, prompt, completion, embed, count} = entry
      # 100 + 75
      assert prompt == 175
      # 50 + 25
      assert completion == 75
      assert embed == 200
      assert count == 3

      # Clear for next test
      TokenAccumulator.clear()
    end

    test "ignores events without workspace_id" do
      # Emit event without workspace_id
      :telemetry.execute(
        [:concept, :knowledge, :search, :stop],
        %{prompt_tokens: 100, completion_tokens: 50},
        %{}
      )

      # Should not create any entries
      entries = TokenAccumulator.flush()
      assert Enum.empty?(entries)
    end
  end

  describe "AggregateTokens worker" do
    setup do
      {:ok, user} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test_#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
      {:ok, workspace: workspace}
    end

    test "flushes ETS entries to TokenLedger", %{workspace: workspace} do
      day_iso = Date.utc_today() |> Date.to_iso8601()

      # Manually insert entry into ETS (simulating accumulation)
      :ets.insert(
        :knowledge_token_accumulator,
        {{workspace.id, day_iso}, 100, 50, 200, 5}
      )

      # Run the worker
      :ok = AggregateTokens.perform(%Oban.Job{args: %{}})

      # Verify TokenLedger row created
      ledger_entries =
        TokenLedger
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(actor: %SystemActor{}, tenant: workspace.id)

      assert length(ledger_entries) == 1
      [ledger] = ledger_entries
      assert ledger.prompt_tokens == 100
      assert ledger.completion_tokens == 50
      assert ledger.embed_tokens == 200
      assert ledger.request_count == 5

      # Verify ETS was cleared
      entries = TokenAccumulator.flush()

      workspace_entries =
        Enum.filter(entries, fn {{ws_id, _day}, _p, _c, _e, _cnt} ->
          ws_id == workspace.id
        end)

      assert Enum.empty?(workspace_entries)
    end

    test "handles multiple workspaces", %{workspace: workspace} do
      {:ok, user2} =
        Concept.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test_#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      {:ok, [workspace2]} = Concept.Accounts.Workspace.for_user(user2.id, actor: user2)
      day_iso = Date.utc_today() |> Date.to_iso8601()

      # Insert entries for two workspaces
      :ets.insert(
        :knowledge_token_accumulator,
        {{workspace.id, day_iso}, 100, 50, 200, 5}
      )

      :ets.insert(
        :knowledge_token_accumulator,
        {{workspace2.id, day_iso}, 150, 75, 300, 8}
      )

      # Run the worker
      :ok = AggregateTokens.perform(%Oban.Job{args: %{}})

      # Verify both workspaces have ledger entries
      ledger1 =
        TokenLedger
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(actor: %SystemActor{}, tenant: workspace.id)
        |> List.first()

      ledger2 =
        TokenLedger
        |> Ash.Query.filter(workspace_id == ^workspace2.id)
        |> Ash.read!(actor: %SystemActor{}, tenant: workspace2.id)
        |> List.first()

      assert ledger1.prompt_tokens == 100
      assert ledger2.prompt_tokens == 150
    end
  end
end
