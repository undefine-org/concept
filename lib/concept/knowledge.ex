defmodule Concept.Knowledge do
  @moduledoc """
  RAG/GraphRAG over Concept's pages & blocks. Wraps Arcana with
  workspace tenancy + Ash policies.
  """
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  require Ash.Query
  alias Concept.Knowledge.SystemActor

  admin do
    show? true
  end

  resources do
    resource Concept.Knowledge.IngestionJob do
      define :read_ingestion_jobs, action: :read
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
  def report_ingestion_queue_depth do
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
end
