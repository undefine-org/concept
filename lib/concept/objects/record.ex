defmodule Concept.Objects.Record do
  @moduledoc """
  A row of a user-defined `ObjectType`. Its `fields` are a JSONB bag validated
  against the type's `FieldDef`s; relations live in `RecordLink` rows. Records
  carry a workflow `state_id`, an `assignee` (human or agent — both Users),
  and a `created_by` (the acceptor of agent work). A "project" is just a
  `Page` a record points at via `page_id`.

  The canonical, queryable entity of the system — the answer to "what is ready
  and mine?" is a SELECT over this table.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "records"
    repo Concept.Repo

    references do
      reference :object_type, on_delete: :delete
      reference :page, on_delete: :nilify
    end

    custom_indexes do
      index [:workspace_id, :object_type_id, :position]
      index [:workspace_id, :assignee_id]
      index [:workspace_id, :state_id]
      index [:fields], using: "gin", all_tenants?: true
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Create a record of a given object type with an optional initial field map."
      accept [:object_type_id, :fields, :state_id, :assignee_id, :page_id]

      change Concept.Objects.Changes.SetWorkspaceFromTenant
      change relate_actor(:created_by, allow_nil?: true)
      change Concept.Objects.Record.Changes.AssignDefaults
      change Concept.Objects.Record.Changes.ValidateFieldsForType
      change Concept.Objects.Record.Changes.AssignAfterLastSibling
    end

    update :update_fields do
      description "Update a record's field values (validated against its type's fields)."
      accept [:fields]
      require_atomic? false
      change Concept.Objects.Record.Changes.ValidateFieldsForType
      change Concept.Objects.Record.Changes.SyncTitle
    end

    update :transition do
      description "Move a record to a new workflow state, enforcing the transition's guards."
      accept []
      require_atomic? false

      argument :to_state_id, :uuid,
        allow_nil?: false,
        description: "Target workflow state. Must be reachable from the current state."

      change Concept.Objects.Record.Changes.RunTransition
    end

    update :assign do
      description "Assign a record to a user (human or agent), or clear with nil."
      accept [:assignee_id]
    end

    update :reorder do
      description "Reorder a record within its object type."
      accept [:position]
    end

    update :archive do
      description "Archive a record (soft-delete)."
      accept []
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    read :list_for_type do
      description "List all records of an object type, in order."

      argument :object_type_id, :uuid,
        allow_nil?: false,
        description: "Object type whose records to list."

      filter expr(object_type_id == ^arg(:object_type_id))
      prepare build(sort: [position: :asc])
    end

    read :ready do
      description "List records that are ready to pick up: in a :todo-category state, unblocked, and unassigned."

      argument :object_type_id, :uuid,
        allow_nil?: false,
        description: "Object type whose ready records to list."

      filter expr(object_type_id == ^arg(:object_type_id) and is_nil(assignee_id))
      prepare Concept.Objects.Record.Preparations.FilterReady
      prepare build(load: [:state, :object_type])
    end

    read :ready_all do
      description "List all ready-to-pick records across every object type in the workspace: in a :todo-category state, unblocked, and unassigned."

      filter expr(is_nil(assignee_id))
      prepare Concept.Objects.Record.Preparations.FilterReady
      prepare build(load: [:state, :object_type])
    end

    read :mine do
      description "List records assigned to the current actor."
      filter expr(assignee_id == ^actor(:id))
      prepare build(sort: [updated_at: :desc], load: [:state, :object_type])
    end

    read :board do
      description "List an object type's records with workflow state loaded, for board/list views."

      argument :object_type_id, :uuid,
        allow_nil?: false,
        description: "Object type whose records to list."

      filter expr(object_type_id == ^arg(:object_type_id))
      prepare build(sort: [position: :asc], load: [:state])
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

  pub_sub do
    module ConceptWeb.Endpoint
    prefix "workspace"

    publish_all :create, [:workspace_id, "records"], event: "record_created"
    publish_all :update, [:workspace_id, "records"], event: "record_updated"
    publish :archive, [:workspace_id, "records"], event: "record_archived"
  end

  attributes do
    uuid_primary_key :id
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :object_type_id, :uuid, allow_nil?: false, public?: true

    attribute :title, :string, default: "", public?: true, constraints: [allow_empty?: true]
    attribute :fields, :map, default: %{}, public?: true

    attribute :state_id, :uuid, allow_nil?: true, public?: true
    attribute :assignee_id, :uuid, allow_nil?: true, public?: true
    attribute :created_by_id, :uuid, allow_nil?: true, public?: true
    attribute :page_id, :uuid, allow_nil?: true, public?: true

    attribute :position, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :object_type, Concept.Objects.ObjectType,
      attribute_writable?: true,
      source_attribute: :object_type_id,
      destination_attribute: :id

    belongs_to :assignee, Concept.Accounts.User,
      attribute_writable?: true,
      source_attribute: :assignee_id,
      destination_attribute: :id

    belongs_to :created_by, Concept.Accounts.User,
      attribute_writable?: true,
      source_attribute: :created_by_id,
      destination_attribute: :id

    belongs_to :page, Concept.Pages.Page,
      attribute_writable?: true,
      source_attribute: :page_id,
      destination_attribute: :id

    belongs_to :state, Concept.Objects.WorkflowState,
      attribute_writable?: true,
      source_attribute: :state_id,
      destination_attribute: :id

    has_many :outgoing_links, Concept.Objects.RecordLink, destination_attribute: :from_record_id
  end
end
