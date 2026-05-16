defmodule Concept.Knowledge.IngestionJob do
  @moduledoc """
  Tracked Ash resource for page ingestion jobs.
  
  AshOban trigger picks up queued rows; state transitions broadcast to PubSub
  for the IndexingPill UI.
  
  States: queued → running → succeeded | failed
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshArchival.Resource, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "knowledge_ingestion_jobs"
    repo Concept.Repo

    references do
      reference :page, on_delete: :nilify
    end

    custom_indexes do
      index [:workspace_id, :state]
      index [:workspace_id, :page_id]
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? false
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  state_machine do
    initial_states [:queued]
    default_initial_state :queued

    transitions do
      transition :start, from: :queued, to: :running
      transition :succeed, from: :running, to: :succeeded
      transition :fail, from: :running, to: :failed
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :page_id, :uuid, allow_nil?: false, public?: true
    attribute :op, :atom, constraints: [one_of: [:upsert, :delete]], default: :upsert, public?: true
    attribute :state, :atom, default: :queued, public?: true, allow_nil?: false, constraints: [one_of: [:queued, :running, :succeeded, :failed]]
    attribute :scheduled_at, :utc_datetime_usec, public?: true
    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :finished_at, :utc_datetime_usec, public?: true
    attribute :chunk_count, :integer, public?: true
    attribute :embed_tokens, :integer, public?: true
    attribute :error_kind, :atom, public?: true
    attribute :error_message, :string, public?: true
    attribute :attempt, :integer, default: 0, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  oban do
    triggers do
      trigger :process do
        action :run
        where expr(state == :queued)
        scheduler_cron "* * * * *"
        queue :knowledge_ingest
        use_tenant_from_record? true
        scheduler_module_name Concept.Knowledge.IngestionJob.AshOban.Scheduler.Process
        worker_module_name Concept.Knowledge.IngestionJob.AshOban.Worker.Process
      end
    end
  end

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    publish :start, ["*", :workspace_id, "ingest"], event: "ingest_started"
    publish :succeed, ["*", :workspace_id, "ingest"], event: "ingest_succeeded"
    publish :fail, ["*", :workspace_id, "ingest"], event: "ingest_failed"
  end

  actions do
    defaults [:read]

    create :enqueue do
      accept [:page_id, :op]
      argument :workspace_id, :uuid, allow_nil?: false
      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Knowledge.IngestionJob.Changes.SetScheduledAt
    end

    update :run do
      accept []
      require_atomic? false
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:attempt, expr(attempt + 1))
      change Concept.Knowledge.IngestionJob.Changes.PerformIngest
    end

    update :succeed do
      accept [:chunk_count, :embed_tokens]
      require_atomic? false
      change transition_state(:succeeded)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_kind, :error_message]
      require_atomic? false
      change transition_state(:failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:system?, true)
    end
  end
end
