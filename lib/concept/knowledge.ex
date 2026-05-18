defmodule Concept.Knowledge do
  @moduledoc """
  RAG/GraphRAG over Concept's pages & blocks. Wraps Arcana with
  workspace tenancy + Ash policies.
  """
  use Ash.Domain,
    otp_app: :concept,
    extensions: [AshAdmin.Domain, AshAi, Concept.AutoTools]

  require Ash.Query
  alias Concept.Knowledge.SystemActor

  admin do
    show? true
  end

  tools do
    tool :search_workspace, Concept.Knowledge.Tools, :search_workspace do
      description "Hybrid vector+graph search over the workspace's pages and blocks."
    end

    tool :answer_question, Concept.Knowledge.Tools, :answer_question do
      description "Answer a question using workspace content with citations."
    end

    tool :link_blocks, Concept.Knowledge.Link, :create do
      description "Assert a relationship between two blocks."
    end
  end

  resources do
    resource Concept.Knowledge.IngestionJob do
      define :read_ingestion_jobs, action: :read
      define :recent_ingestion_jobs, action: :recent_for_workspace
    end

    resource Concept.Knowledge.Citation do
      define :create_citation, action: :create
      define :citations_for_message, action: :for_message, args: [:message_id]
      define :citations_for_block, action: :for_block, args: [:block_id]
    end

    resource Concept.Knowledge.Link do
      define :create_link, action: :create
      define :destroy_link, action: :destroy
    end

    resource Concept.Knowledge.Link.Version

    resource Concept.Knowledge.TokenLedger do
      define :read_token_ledger, action: :read
    end

    resource Concept.Knowledge.Tools
  end

  @doc """
  Enqueue a page ingestion job.

  Creates an IngestionJob row in :queued state. The AshOban trigger picks it up
  on the next cron tick.
  """
  def enqueue_ingest!(workspace_id, page_id, op \\ :upsert) do
    Concept.Knowledge.IngestionJob
    |> Ash.Changeset.for_create(:enqueue, %{workspace_id: workspace_id, page_id: page_id, op: op})
    |> Ash.create!(actor: %SystemActor{}, tenant: workspace_id)
  end

  @doc """
  Reports ingestion queue depth for telemetry periodic measurements.
  Counts IngestionJob rows in :queued state across all workspaces.
  Emits telemetry event consumed by Telemetry.Metrics.last_value/1.
  """
  # Reads raw SQL count to bypass multitenant TenantRequired; safe since this is a process-wide metric.
  # Defensive: telemetry_poller starts before Concept.Repo (see application.ex child order), and if a
  # measurement raises, telemetry_poller blacklists it for the rest of the VM lifetime
  # (make_measurements_and_filter_misbehaving/1). We short-circuit when the Repo isn't registered and
  # rescue any unexpected error so the metric keeps ticking. See BUG-042.
  def report_ingestion_queue_depth do
    if Process.whereis(Concept.Repo) do
      import Ecto.Query

      count =
        Concept.Repo.aggregate(
          from(j in "knowledge_ingestion_jobs",
            where: j.state == "queued" and is_nil(j.archived_at)
          ),
          :count
        )

      :telemetry.execute(
        [:concept, :knowledge, :ingestion_job, :queue],
        %{depth: count},
        %{}
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc "Returns workspace graph for visualization."
  def graph_for_workspace(workspace_id),
    do: Concept.Knowledge.GraphQuery.graph_for_workspace(workspace_id)
end
