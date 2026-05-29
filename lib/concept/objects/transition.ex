defmodule Concept.Objects.Transition do
  @moduledoc """
  A directed edge in a `Workflow`: `from_state → to_state`, carrying an ordered
  list of `guards` (the *user plane* composition). Each guard is
  `%{"kind" => "...", "config" => %{...}}` resolved at transition time by
  `Concept.Objects.Record.Changes.RunTransition`.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table "transitions"
    repo Concept.Repo

    references do
      reference :workflow, on_delete: :delete
      reference :from_state, on_delete: :delete
      reference :to_state, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :workflow_id, :from_state_id]
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Define an allowed transition between two workflow states, with optional guards."
      accept [:workflow_id, :from_state_id, :to_state_id, :guards]
      change Concept.Objects.Changes.SetWorkspaceFromTenant
    end

    update :set_guards do
      description "Replace the guard list on a transition."
      accept [:guards]
    end

    read :list_for_workflow do
      description "List a workflow's transitions."

      argument :workflow_id, :uuid,
        allow_nil?: false,
        description: "Workflow whose transitions to list."

      filter expr(workflow_id == ^arg(:workflow_id))
    end

    read :from_state do
      description "List transitions leaving a given state."

      argument :from_state_id, :uuid,
        allow_nil?: false,
        description: "Source state whose outgoing transitions to list."

      filter expr(from_state_id == ^arg(:from_state_id))
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Concept.Pages.Checks.WorkspaceMemberCreate
    end

    policy action_type([:update, :destroy]) do
      authorize_if Concept.Pages.Checks.WorkspaceMember
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :workflow_id, :uuid, allow_nil?: false, public?: true
    attribute :from_state_id, :uuid, allow_nil?: false, public?: true
    attribute :to_state_id, :uuid, allow_nil?: false, public?: true

    attribute :guards, {:array, :map},
      default: [],
      public?: true,
      description: ~s|Ordered guard specs: [%{"kind" => "...", "config" => %{...}}].|

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workflow, Concept.Objects.Workflow,
      attribute_writable?: true,
      source_attribute: :workflow_id,
      destination_attribute: :id

    belongs_to :from_state, Concept.Objects.WorkflowState,
      attribute_writable?: true,
      source_attribute: :from_state_id,
      destination_attribute: :id

    belongs_to :to_state, Concept.Objects.WorkflowState,
      attribute_writable?: true,
      source_attribute: :to_state_id,
      destination_attribute: :id
  end
end
