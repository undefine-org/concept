defmodule Concept.Objects.RecordLink do
  @moduledoc """
  A typed edge between two `Record`s, carrying which `FieldDef` (relation) it
  realizes. All relation-field values and `blocked_by` dependencies are stored
  as `RecordLink` rows so edges are queryable in SQL (readiness derivation,
  graph views) rather than buried in JSONB.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "record_links"
    repo Concept.Repo

    references do
      reference :from_record, on_delete: :delete
      reference :to_record, on_delete: :delete
      reference :field_def, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :from_record_id]
      index [:workspace_id, :to_record_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Link one record to another along a relation field."
      accept [:from_record_id, :to_record_id, :field_def_id]

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace the link belongs to. Actor must be a member."

      change set_attribute(:workspace_id, arg(:workspace_id))
    end

    destroy :destroy do
      description "Remove a link between two records."
    end

    read :from_record do
      description "List all links originating from a record."

      argument :from_record_id, :uuid,
        allow_nil?: false,
        description: "The source record whose outgoing links to list."

      filter expr(from_record_id == ^arg(:from_record_id))
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
    attribute :from_record_id, :uuid, allow_nil?: false, public?: true
    attribute :to_record_id, :uuid, allow_nil?: false, public?: true
    attribute :field_def_id, :uuid, allow_nil?: true, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :from_record, Concept.Objects.Record,
      attribute_writable?: true,
      source_attribute: :from_record_id,
      destination_attribute: :id

    belongs_to :to_record, Concept.Objects.Record,
      attribute_writable?: true,
      source_attribute: :to_record_id,
      destination_attribute: :id

    belongs_to :field_def, Concept.Objects.FieldDef,
      attribute_writable?: true,
      source_attribute: :field_def_id,
      destination_attribute: :id
  end
end
