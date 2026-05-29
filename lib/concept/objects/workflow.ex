defmodule Concept.Objects.Workflow do
  @moduledoc """
  A named lifecycle: an ordered set of `WorkflowState`s and the `Transition`s
  between them. An `ObjectType` points at one workflow; its records move
  through the workflow's states under the transitions' guards.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table "workflows"
    repo Concept.Repo
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Create a workflow (a lifecycle) in the workspace."
      accept [:name]
      change Concept.Objects.Changes.SetWorkspaceFromTenant
    end

    update :rename do
      description "Rename a workflow."
      accept [:name]
    end

    read :list do
      description "List all workflows defined in the workspace."
      prepare build(sort: [inserted_at: :asc])
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
    attribute :name, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :states, Concept.Objects.WorkflowState, destination_attribute: :workflow_id
    has_many :transitions, Concept.Objects.Transition, destination_attribute: :workflow_id
  end
end
