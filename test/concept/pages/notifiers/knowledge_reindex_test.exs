defmodule Concept.Pages.Notifiers.KnowledgeReindexTest do
  use Concept.DataCase, async: true
  use Oban.Testing, repo: Concept.Repo

  alias Concept.Knowledge.Workers.IngestPage
  alias Concept.Pages

  setup do
    # Create a test user and workspace
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    %{user: user, workspace: workspace}
  end

  describe "KnowledgeReindex notifier" do
    test "creating a block enqueues IngestPage job with page_id", %{user: user, workspace: workspace} do
      {:ok, page} = Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

      {:ok, _block} =
        Pages.create_block(page.id, :paragraph, workspace.id, nil, actor: user, tenant: workspace.id)

      # Assert exactly one job was enqueued for this page
      assert_enqueued worker: IngestPage, args: %{page_id: page.id, op: :upsert}
    end

    test "two page updates within debounce window collapse to one job", %{user: user, workspace: workspace} do
      {:ok, page} = Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

      # Clear the job queue from page creation
      Oban.drain_queue(queue: :knowledge_ingest)

      # Update the page twice in quick succession
      {:ok, _} = Pages.rename_page(page, "New Title 1", actor: user, tenant: workspace.id)
      {:ok, _} = Pages.set_icon(page, "🔥", actor: user, tenant: workspace.id)

      # Due to Oban unique constraint with 5-second period and same keys, should only have 1 job
      jobs = all_enqueued(worker: IngestPage, args: %{page_id: page.id, op: :upsert})
      assert length(jobs) == 1
    end

    test "creating blocks on different pages enqueues separate jobs", %{user: user, workspace: workspace} do
      {:ok, page_a} = Pages.create_page("Page A", workspace.id, nil, actor: user, tenant: workspace.id)
      {:ok, page_b} = Pages.create_page("Page B", workspace.id, nil, actor: user, tenant: workspace.id)

      # Clear creation jobs
      Oban.drain_queue(queue: :knowledge_ingest)

      {:ok, _} =
        Pages.create_block(page_a.id, :paragraph, workspace.id, nil, actor: user, tenant: workspace.id)

      {:ok, _} =
        Pages.create_block(page_b.id, :paragraph, workspace.id, nil, actor: user, tenant: workspace.id)

      # Should have jobs for both pages
      assert_enqueued worker: IngestPage, args: %{page_id: page_a.id, op: :upsert}
      assert_enqueued worker: IngestPage, args: %{page_id: page_b.id, op: :upsert}
    end

    test "archiving a page enqueues job with op: :delete", %{user: user, workspace: workspace} do
      {:ok, page} = Pages.create_page("To Archive", workspace.id, nil, actor: user, tenant: workspace.id)

      # Clear creation job
      Oban.drain_queue(queue: :knowledge_ingest)

      {:ok, _} = Pages.archive(page, actor: user, tenant: workspace.id)

      # Should enqueue delete job
      assert_enqueued worker: IngestPage, args: %{page_id: page.id, op: :delete}
    end

    test "updating page metadata (rename) enqueues job with op: :upsert", %{user: user, workspace: workspace} do
      {:ok, page} = Pages.create_page("Original Title", workspace.id, nil, actor: user, tenant: workspace.id)

      # Clear creation job
      Oban.drain_queue(queue: :knowledge_ingest)

      {:ok, _} = Pages.rename_page(page, "New Title", actor: user, tenant: workspace.id)

      # Should enqueue upsert job for page update
      assert_enqueued worker: IngestPage, args: %{page_id: page.id, op: :upsert}
    end

    test "archiving a block enqueues upsert (not delete)", %{user: user, workspace: workspace} do
      {:ok, page} = Pages.create_page("Test Page", workspace.id, nil, actor: user, tenant: workspace.id)

      {:ok, block} =
        Pages.create_block(page.id, :paragraph, workspace.id, nil, actor: user, tenant: workspace.id)

      # Clear creation job
      Oban.drain_queue(queue: :knowledge_ingest)

      {:ok, _} = Pages.archive_block(block, actor: user, tenant: workspace.id)

      # Block archive should trigger page upsert, not delete
      assert_enqueued worker: IngestPage, args: %{page_id: page.id, op: :upsert}
    end
  end
end
