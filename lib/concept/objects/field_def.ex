defmodule Concept.Objects.FieldDef do
  @moduledoc """
  A field definition on an `ObjectType`: name, key, field type, required flag,
  and per-field `config` (e.g. select options, relation target). Ordered via
  fractional index. Records validate their `fields` bag against these defs.
  """
  use Concept.Resources.WorkspaceTenanted,
    otp_app: :concept,
    domain: Concept.Objects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table "field_defs"
    repo Concept.Repo

    references do
      reference :object_type, on_delete: :delete
    end

    custom_indexes do
      index [:workspace_id, :object_type_id, :position]
      index [:object_type_id, :key], unique: true
    end
  end

  archive do
    attribute :archived_at
    base_filter?(true)
  end

  actions do
    defaults [:read]

    create :create do
      description "Add a field to an object type."

      accept [
        :object_type_id,
        :name,
        :key,
        :field_type,
        :required?,
        :config,
        :is_title?,
        :position
      ]

      change Concept.Objects.Changes.SetWorkspaceFromTenant
      change Concept.Objects.Changes.SlugifyKey
      change Concept.Objects.FieldDef.Changes.AssignAfterLastSibling
    end

    update :update_def do
      description "Update a field definition's name, required flag, or config."
      accept [:name, :required?, :config]
    end

    update :reorder do
      description "Reorder a field within its object type."
      accept [:position]
    end

    read :list_for_type do
      description "List all fields of an object type, in display order."

      argument :object_type_id, :uuid,
        allow_nil?: false,
        description: "Object type whose fields to list."

      filter expr(object_type_id == ^arg(:object_type_id))
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
    attribute :object_type_id, :uuid, allow_nil?: false, public?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :field_type, Concept.Objects.FieldTypeAttr, allow_nil?: false, public?: true
    attribute :required?, :boolean, default: false, public?: true
    attribute :config, :map, default: %{}, public?: true

    attribute :is_title?, :boolean,
      default: false,
      public?: true,
      description: "Whether this field is the record's display title."

    attribute :position, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :object_type, Concept.Objects.ObjectType,
      attribute_writable?: true,
      source_attribute: :object_type_id,
      destination_attribute: :id
  end
end
