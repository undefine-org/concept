defmodule Concept.Knowledge.TokenLedgerTest do
  use Concept.DataCase, async: true
  require Ash.Query

  alias Concept.Knowledge
  alias Concept.Knowledge.TokenLedger
  alias Concept.Knowledge.SystemActor

  describe "upsert action" do
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

    test "creates a new row with token counts", %{workspace: workspace} do
      today = Date.utc_today()

      {:ok, ledger} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: today,
          prompt_tokens: 100,
          completion_tokens: 50,
          embed_tokens: 200,
          request_count: 5
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      assert ledger.workspace_id == workspace.id
      assert ledger.day == today
      assert ledger.prompt_tokens == 100
      assert ledger.completion_tokens == 50
      assert ledger.embed_tokens == 200
      assert ledger.request_count == 5
    end

    test "upserts on existing workspace_id + day", %{workspace: workspace} do
      today = Date.utc_today()

      # Create initial row
      {:ok, _ledger1} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: today,
          prompt_tokens: 100,
          completion_tokens: 50,
          embed_tokens: 200,
          request_count: 5
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      # Upsert with new values
      {:ok, ledger2} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: today,
          prompt_tokens: 150,
          completion_tokens: 75,
          embed_tokens: 300,
          request_count: 8
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      # Should update, not insert
      assert ledger2.prompt_tokens == 150
      assert ledger2.completion_tokens == 75
      assert ledger2.embed_tokens == 300
      assert ledger2.request_count == 8

      # Verify only one row exists
      results =
        TokenLedger
        |> Ash.Query.filter(workspace_id == ^workspace.id and day == ^today)
        |> Ash.read!(actor: %SystemActor{}, tenant: workspace.id)

      assert length(results) == 1
    end

    test "allows different days for same workspace", %{workspace: workspace} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      {:ok, _ledger1} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: today,
          prompt_tokens: 100,
          completion_tokens: 50,
          embed_tokens: 200,
          request_count: 5
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      {:ok, _ledger2} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: yesterday,
          prompt_tokens: 150,
          completion_tokens: 75,
          embed_tokens: 300,
          request_count: 8
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      results =
        TokenLedger
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(actor: %SystemActor{}, tenant: workspace.id)

      assert length(results) == 2
    end
  end

  describe "policies" do
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
      {:ok, workspace: workspace, user: user}
    end

    test "system actor can create", %{workspace: workspace} do
      {:ok, _ledger} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: Date.utc_today(),
          prompt_tokens: 100,
          completion_tokens: 50,
          embed_tokens: 200,
          request_count: 5
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)
    end

    test "workspace member can read", %{workspace: workspace, user: user} do
      # User is already a member through the setup workspace creation

      # Create ledger entry
      {:ok, _ledger} =
        TokenLedger
        |> Ash.Changeset.for_create(:upsert, %{
          workspace_id: workspace.id,
          day: Date.utc_today(),
          prompt_tokens: 100,
          completion_tokens: 50,
          embed_tokens: 200,
          request_count: 5
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      # Member should be able to read
      results =
        TokenLedger
        |> Ash.read!(actor: user, tenant: workspace.id)

      assert length(results) == 1
    end
  end
end
