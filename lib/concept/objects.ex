defmodule Concept.Objects do
  @moduledoc """
  The Objects domain: a runtime database builder.

  Workspaces define their own object *types* (`ObjectType`), *fields*
  (`FieldDef`), and *workflows* (`Workflow`/`WorkflowState`/`Transition`);
  rows are `Record`s with a validated JSONB field-bag and `RecordLink` edges.

  **Task** is the first built-in type — seeded per workspace — not a special
  resource. See `docs/objects_and_tasks.md`.
  """
  use Ash.Domain,
    otp_app: :concept,
    extensions: [AshAdmin.Domain, AshAi, Concept.AutoTools]

  admin do
    show? true
  end

  resources do
    resource Concept.Objects.ObjectType do
      define :create_object_type, action: :create, args: [:workspace_id, :name]
      define :rename_object_type, args: [:name], action: :rename
      define :list_object_types, action: :list
      define :get_object_type, action: :read, get_by: :id
    end

    resource Concept.Objects.FieldDef do
      define :create_field_def,
        action: :create,
        args: [:object_type_id, :name, :field_type]

      define :update_field_def, args: [:name, :required?, :config], action: :update_def
      define :reorder_field_def, args: [:position], action: :reorder
      define :list_field_defs, args: [:object_type_id], action: :list_for_type
    end

    resource Concept.Objects.Record do
      define :create_record, action: :create, args: [:object_type_id]
      define :update_record_fields, args: [:fields], action: :update_fields
      define :transition_record, args: [:to_state_id], action: :transition
      define :assign_record, args: [:assignee_id], action: :assign
      define :reorder_record, args: [:position], action: :reorder
      define :archive_record, action: :archive
      define :list_records, args: [:object_type_id], action: :list_for_type
      define :ready_records, args: [:object_type_id], action: :ready
      define :my_records, action: :mine
      define :get_record, action: :read, get_by: :id
    end

    resource Concept.Objects.RecordLink do
      define :link_records, args: [:from_record_id, :to_record_id, :field_def_id], action: :create
      define :unlink_records, action: :destroy
      define :list_links_from, args: [:from_record_id], action: :from_record
    end
  end
end
