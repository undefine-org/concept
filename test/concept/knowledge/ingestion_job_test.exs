defmodule Concept.Knowledge.IngestionJobTest do
  use Concept.DataCase, async: true

  import Phoenix.ChannelTest

  alias Concept.Knowledge
  alias Concept.Knowledge.{IngestionJob, SystemActor}

  @endpoint ConceptWeb.Endpoint

  describe "enqueue_ingest!/3" do
    test "creates a job in :queued state with workspace+page" do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)

      job = Knowledge.enqueue_ingest!(workspace.id, page.id, :upsert)

      assert job.workspace_id == workspace.id
      assert job.page_id == page.id
      assert job.op == :upsert
      assert job.state == :queued
      assert job.scheduled_at
      assert job.attempt == 0
    end

    test "sets scheduled_at ~2s in the future" do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)

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
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id, title: "Test Page")
      _block = block_fixture(workspace_id: workspace.id, page_id: page.id, content: %{"text" => "Test content"})

      # Mock Arcana module
      mock_arcana = fn _text, opts ->
        # Return success with chunk count
        {:ok, %{chunks: 3}}
      end

      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      %{workspace: workspace, page: page, mock_arcana: mock_arcana}
    end

    test "transitions queued -> running -> succeeded", %{workspace: workspace, page: page} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      assert job.state == :queued

      # Run the job
      {:ok, updated_job} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      # Should transition to succeeded
      reloaded = Ash.get!(IngestionJob, updated_job.id, actor: %SystemActor{}, tenant: workspace.id)
      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 3
      assert reloaded.started_at
      assert reloaded.finished_at
      assert reloaded.attempt == 1
    end

    test "handles page not found gracefully", %{workspace: workspace} do
      fake_page_id = Ash.UUID.generate()
      job = Knowledge.enqueue_ingest!(workspace.id, fake_page_id)

      {:ok, updated_job} =
        job
        |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
        |> Ash.update()

      reloaded = Ash.get!(IngestionJob, updated_job.id, actor: %SystemActor{}, tenant: workspace.id)
      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 0
    end
  end

  describe "PubSub broadcasts" do
    setup do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)
      _block = block_fixture(workspace_id: workspace.id, page_id: page.id)

      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      # Subscribe to workspace ingest events
      topic = "workspace:*:#{workspace.id}:ingest"
      @endpoint.subscribe(topic)

      %{workspace: workspace, page: page, topic: topic}
    end

    test "broadcasts ingest_started on :start transition", %{workspace: workspace, page: page} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Manually trigger :start (normally done by :run)
      job
      |> Ash.Changeset.for_update(:start, %{}, actor: %SystemActor{}, tenant: workspace.id)
      |> Ash.update!()

      assert_broadcast "ingest_started", _payload
    end

    test "broadcasts ingest_succeeded on successful run", %{workspace: workspace, page: page} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      job
      |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
      |> Ash.update!()

      assert_broadcast "ingest_succeeded", _payload
    end

    test "broadcasts ingest_failed on error", %{workspace: workspace, page: page} do
      # Mock Arcana to fail
      Application.put_env(:concept, :arcana_module, MockArcanaFail)

      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      job
      |> Ash.Changeset.for_update(:run, %{}, actor: %SystemActor{}, tenant: workspace.id)
      |> Ash.update!()

      assert_broadcast "ingest_failed", _payload

      Application.put_env(:concept, :arcana_module, MockArcana)
    end
  end

  describe "AshOban trigger" do
    setup do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)
      _block = block_fixture(workspace_id: workspace.id, page_id: page.id)

      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

      %{workspace: workspace, page: page}
    end

    test "picks up queued rows when triggered", %{workspace: workspace, page: page} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)
      assert job.state == :queued

      # Manually trigger the AshOban worker
      AshOban.Test.trigger(IngestionJob, :process, [job])

      # Reload and verify state transition
      reloaded = Ash.get!(IngestionJob, job.id, actor: %SystemActor{}, tenant: workspace.id)
      assert reloaded.state == :succeeded
      assert reloaded.chunk_count == 3
    end
  end

  describe "policies" do
    setup do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)
      member = user_fixture()
      non_member = user_fixture()

      # Add member to workspace
      membership_fixture(workspace_id: workspace.id, user_id: member.id)

      %{workspace: workspace, page: page, member: member, non_member: non_member}
    end

    test "workspace member can read jobs", %{workspace: workspace, page: page, member: member} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Member should be able to read
      result = Ash.get(IngestionJob, job.id, actor: member, tenant: workspace.id)
      assert {:ok, _job} = result
    end

    test "non-member cannot read jobs", %{workspace: workspace, page: page, non_member: non_member} do
      job = Knowledge.enqueue_ingest!(workspace.id, page.id)

      # Non-member should not be able to read
      result = Ash.get(IngestionJob, job.id, actor: non_member, tenant: workspace.id)
      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "non-system actor cannot create job", %{workspace: workspace, page: page, member: member} do
      # Attempt to create job as regular user
      result =
        IngestionJob
        |> Ash.Changeset.for_create(:enqueue, %{workspace_id: workspace.id, page_id: page.id, op: :upsert})
        |> Ash.create(actor: member, tenant: workspace.id)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "system actor can create job", %{workspace: workspace, page: page} do
      result =
        IngestionJob
        |> Ash.Changeset.for_create(:enqueue, %{workspace_id: workspace.id, page_id: page.id, op: :upsert})
        |> Ash.create(actor: %SystemActor{}, tenant: workspace.id)

      assert {:ok, _job} = result
    end
  end

  describe "archival" do
    test "archived jobs excluded from default reads" do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)
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

      # Load all (including archived)
      all_jobs = Ash.read!(IngestionJob, actor: %SystemActor{}, tenant: workspace.id, load_archived?: true)
      assert Enum.any?(all_jobs, &(&1.id == job.id))
    end
  end

  describe "concurrent jobs" do
    test "concurrent jobs for same page allowed", %{} do
      workspace = workspace_fixture()
      page = page_fixture(workspace_id: workspace.id)
      _block = block_fixture(workspace_id: workspace.id, page_id: page.id)

      Application.put_env(:concept, :arcana_module, MockArcana)

      on_exit(fn ->
        Application.delete_env(:concept, :arcana_module)
      end)

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
end

# Mock modules for testing
defmodule MockArcana do
  def ingest(_text, _opts) do
    {:ok, %{chunks: 3}}
  end
end

defmodule MockArcanaFail do
  def ingest(_text, _opts) do
    {:error, %{reason: :rate_limited}}
  end
end
