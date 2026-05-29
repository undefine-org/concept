defmodule Concept.Objects.ObjectType do
  @moduledoc """
  A user-defined object *type* within a workspace (e.g. "Task", "Customer").
  The schema-layer entity of the database builder: it owns a set of
  `FieldDef`s and points at a `Workflow` (its lifecycle). Built-in types
  (`is_system?`) are seeded and cannot be deleted.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table "object_types"
    repo Concept.Repo

    custom_indexes do
      index [:workspace_id, :key], unique: true
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Create a new object type (a kind of record) in the workspace."
      accept [:name, :key, :icon, :color, :workflow_id, :is_system?]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the object type belongs to. Actor must be a member."

      change set_attribute(:workspace_id, arg(:workspace_id))
      change Concept.Objects.Changes.SlugifyKey
    end

    update :rename do
      description "Rename an object type."
      accept [:name]
    end

    update :set_workflow do
      description "Set the workflow (lifecycle) used by records of this type."
      accept [:workflow_id]
    end

    read :list do
      description "List all object types defined in the workspace."
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
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :icon, :string, default: "📋", public?: true
    attribute :color, :atom, default: :default, public?: true

    attribute :workflow_id, :uuid, allow_nil?: true, public?: true

    attribute :is_system?, :boolean, default: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :field_defs, Concept.Objects.FieldDef, destination_attribute: :object_type_id
    has_many :records, Concept.Objects.Record, destination_attribute: :object_type_id
  end

  aggregates do
    count :field_count, :field_defs
    count :record_count, :records
  end
end
