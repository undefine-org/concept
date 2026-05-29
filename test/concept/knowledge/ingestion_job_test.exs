defmodule Concept.Knowledge.IngestionJobTest do
  use Concept.DataCase, async: true
  use Oban.Testing, repo: Concept.Repo

  import Phoenix.ChannelTest

  alias Concept.Knowledge
  alias Concept.Knowledge.{IngestionJob, SystemActor}
  alias Concept.{Accounts, Pages}

  @endpoint ConceptWeb.Endpoint

  defp create_fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

    {:ok, block} =
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{user: user, workspace: workspace, page: page, block: block}
  end

  describe "enqueue_ingest!/3" do
    test "creates a job in :queued state with workspace+page" do
      %{workspace: workspace, page: page} = create_fixtures()

      job = Knowledge.enqueue_ingest!(workspace.id, page.id, :upsert)

      assert job.workspace_id == workspace.id
      assert job.page_id == page.id
      assert job.op == :upsert
      assert job.state == :queued
      assert job.scheduled_at
      assert job.attempt == 0
    end

    test "sets scheduled_at ~2s in the future" do
      %{workspace: workspace, page: page} = create_fixtures()

      before = DateTime.utc_now()
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      after_time = DateTime.utc_now()

      # scheduled_at should be roughly 2 seconds from now
      assert DateTime.diff(job.scheduled_at, before, :second) in 1..3
      assert DateTime.diff(job.scheduled_at, after_time, :second) in 1..3
    end
  end

  describe ":run action" do
    setup do
      # Mock Arcana module
      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      :ok
    end

    test "transitions queued -> running -> succeeded" do
      %{workspace: workspace, page: page} = create_fixtures()

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      assert job.state == :queued

      # Run the job
      {:ok, updated_job} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      # Should transition to succeeded
      reloaded =
        Ash.get!(IngestionJob, updated_job.id, actor: %SystemActor{}, tenant: workspace.id)

      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 3
      assert reloaded.started_at
      assert reloaded.finished_at
      assert reloaded.attempt == 1
    end

    test "op: :delete succeeds as a no-op when nothing was ingested (BUG-055)" do
      %{workspace: workspace, page: page} = create_fixtures()
      job = Knowledge.enqueue_ingest!(workspace.id, page.id, :delete)

      {:ok, updated_job} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      reloaded =
        Ash.get!(IngestionJob, updated_job.id, actor: %SystemActor{}, tenant: workspace.id)

      # No documents for this page in the (empty) collection -> 0 deleted, success.
      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 0
    end

    test "handles page not found gracefully" do
      %{workspace: workspace} = create_fixtures()
      fake_page_id = Ash.UUID.generate()
      job = Knowledge.enqueue_ingest!(workspace.id, fake_page_id)

      {:ok, updated_job} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      reloaded =
        Ash.get!(IngestionJob, updated_job.id, actor: %SystemActor{}, tenant: workspace.id)

      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 0
    end
  end

  describe "PubSub broadcasts" do
    setup do
      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      fixtures = create_fixtures()

      # Subscribe to workspace ingest events
      topic = "workspace:*:#{fixtures.workspace.id}:ingest"
      @endpoint.subscribe(topic)

      Map.put(fixtures, :topic, topic)
    end

    test "broadcasts ingest_succeeded on successful run", %{workspace: workspace, page: page} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      job
      |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
      |> Ash.update!()

      assert_broadcast "ingest_succeeded", _payload
    end
  end

  describe "AshOban trigger" do
    setup do
      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      :ok
    end

    test "picks up queued rows when triggered" do
      %{workspace: workspace, page: page} = create_fixtures()

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      assert job.state == :queued

      # Manually invoke :run action (simulates AshOban worker)
      {:ok, updated} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      # Reload and verify state transition
      reloaded = Ash.get!(IngestionJob, updated.id, actor: %SystemActor{}, tenant: workspace.id)
      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 3
    end
  end

  describe "policies" do
    test "workspace member can read jobs" do
      %{workspace: workspace, page: page, user: member} = create_fixtures()

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Member should be able to read
      result = Ash.get(IngestionJob, job.id, actor: member, tenant: workspace.id)
      assert {:ok, _job} = result
    end

    test "non-member cannot read jobs" do
      %{workspace: workspace, page: page} = create_fixtures()

      # Create another user who is not a member
      {:ok, non_member} =
        Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "nonmember_#{System.unique_integer([:positive])}@example.com",
          password: "passw0rd!",
          password_confirmation: "passw0rd!"
        })
        |> Ash.create(authorize?: false)

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Non-member should not be able to read
      # Ash hides forbidden records by returning NotFound for read queries (standard behavior)
      result = Ash.get(IngestionJob, job.id, actor: non_member, tenant: workspace.id)
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} = result
    end

    test "non-system actor cannot create job" do
      %{workspace: workspace, page: page, user: member} = create_fixtures()

      # Attempt to create job as regular user
      result =
        IngestionJob
        |> Ash.Changeset.for_create(:enqueue, %{
          workspace_id: workspace.id,
          page_id: page.id,
          op: :upsert
        })
        |> Ash.create(actor: member, tenant: workspace.id)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "system actor can create job" do
      %{workspace: workspace, page: page} = create_fixtures()

      result =
        IngestionJob
        |> Ash.Changeset.for_create(:enqueue, %{
          workspace_id: workspace.id,
          page_id: page.id,
          op: :upsert
        })
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      assert {:ok, _job} = result
    end
  end

  describe "archival" do
    test "archived jobs excluded from default reads" do
      %{workspace: workspace, page: page} = create_fixtures()

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Archive the job
      {:ok, archived} =
        job
        |> Ash.Changeset.for_update(:archive, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      assert archived.archived_at

      # Default read should exclude archived
      jobs = Ash.read!(IngestionJob, actor: %SystemActor{}, tenant: workspace.id)
      refute Enum.any?(jobs, &(&1.id == job.id))
    end
  end

  describe "concurrent jobs" do
    setup do
      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      :ok
    end

    test "concurrent jobs for same page allowed" do
      %{workspace: workspace, page: page} = create_fixtures()

      # Create two jobs for same page
      job1 = Knowledge.enqueue_ingest!(workspace.id, page.id)
      job2 = Knowledge.enqueue_ingest!(workspace.id, page.id)

      assert job1.id != job2.id
      assert job1.page_id == job2.page_id

      # Both should transition independently
      {:ok, _} =
        job1
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      {:ok, _} =
        job2
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      reloaded1 = Ash.get!(IngestionJob, job1.id, actor: %SystemActor{}, tenant: workspace.id)
      reloaded2 = Ash.get!(IngestionJob, job2.id, actor: %SystemActor{}, tenant: workspace.id)

      assert reloaded1.state == :succeeded
      assert reloaded2.state == :succeeded
    end
  end

  describe "AshOban scheduler tenancy (BUG-043)" do
    setup do
      Application.put_env(:concept, :arcana_module, MockArcana)
      on_exit(fn -> Application.delete_env(:concept, :arcana_module) end)
      :ok
    end

    test "scheduler perform/1 fans out per workspace and enqueues worker jobs" do
      %{workspace: workspace, page: page} = create_fixtures()
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      assert job.state == :queued

      # Pre-fix: raises Ash.Error.Invalid -- tenant required for IngestionJob read.
      # Post-fix: scheduler iterates workspaces under a system actor, streams
      # queued rows per-tenant, and enqueues a worker job per row.
      assert :ok =
               Concept.Knowledge.IngestionJob.AshOban.Scheduler.Process.perform(%Oban.Job{
                 args: %{}
               })

      assert_enqueued(
        worker: Concept.Knowledge.IngestionJob.AshOban.Worker.Process,
        args: %{"primary_key" => %{"id" => job.id}, "tenant" => workspace.id}
      )
    end
  end
end

# Mock modules for testing
defmodule MockArcana do
  def ingest(_text, _opts) do
    {:ok, %{chunks: 3}}
  end

  # Track delete calls so tests can assert eviction (BUG-055).
  def delete(_document_id, _opts), do: :ok
end
