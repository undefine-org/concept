defmodule Concept.Objects.WorkflowState do
  @moduledoc """
  A named state within a `Workflow`. State *names* are user-customizable and
  open; each maps to exactly one FIXED `category` — the agent-legible contract.

  Categories (closed set): `:backlog :todo :doing :review :done :canceled`.
  Agents reason about `category`, never the workspace-specific `name`, so
  readiness (`category == :todo`) and acceptance (`category == :review`) mean
  the same thing in every workspace.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  @categories [:backlog, :todo, :doing, :review, :done, :canceled]

  postgres do
    table "workflow_states"
    repo Concept.Repo

    references do
      reference :workflow, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :workflow_id, :position]
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Add a state to a workflow. Each state maps to one fixed category."
      accept [:workflow_id, :name, :category, :is_initial?, :position]
      change Concept.Objects.Changes.SetWorkspaceFromTenant
      change Concept.Objects.WorkflowState.Changes.AssignAfterLastSibling
    end

    update :update_state do
      description "Update a workflow state's name or category."
      accept [:name, :category, :is_initial?]
    end

    update :mark_initial do
      description "Mark this state as the workflow's initial state (clears the others)."
      accept []
      require_atomic? false
      change set_attribute(:is_initial?, true)
      change Concept.Objects.WorkflowState.Changes.ClearSiblingInitials
    end

    update :reorder do
      description "Reorder a state within its workflow."
      accept [:position]
    end

    read :list_for_workflow do
      description "List a workflow's states in order."

      argument :workflow_id, :uuid,
        allow_nil?: false,
        description: "Workflow whose states to list."

      filter expr(workflow_id == ^arg(:workflow_id))
      prepare build(sort: [position: :asc])
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

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :category, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @categories],
      description: "Fixed semantic category: backlog|todo|doing|review|done|canceled."

    attribute :is_initial?, :boolean, default: false, public?: true
    attribute :position, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workflow, Concept.Objects.Workflow,
      attribute_writable?: true,
      source_attribute: :workflow_id,
      destination_attribute: :id
  end

  def categories, do: @categories
end
