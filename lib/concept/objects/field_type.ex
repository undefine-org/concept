defmodule Concept.Objects.FieldType do
  @moduledoc """
  Behaviour each field type implements. Consumed by the
  `Concept.Objects.FieldTypes` registry; one module per field kind
  (text, number, select, date, user, relation, checklist, url).

  This is the object-layer analogue of `Concept.Pages.BlockType`: the
  `Record` resource is field-type-agnostic — each type owns its value
  validation, default, casting, and JSON-schema fragment (used by the MCP
  `ToolProjector`).

  ## Relation fields

  `:relation` is special: its values are not stored in the `Record.fields`
  JSONB bag but as first-class `RecordLink` rows. A `:relation` `FieldType`
  therefore validates only the *shape* of an incoming reference (a uuid or
  list of uuids); the engine routes persistence to `RecordLink`.
  """

  @typedoc "The registry key, e.g. `:text`, `:select`."
  @type key :: atom

  @doc "The atom key this type registers under."
  @callback key() :: key

  @doc "Human label for pickers/UI."
  @callback label() :: String.t()

  @doc """
  Validate a stored value against this field's per-field `config`.

  Returns `:ok` or `{:error, message}`. `nil` is always considered valid
  here (the `required?` check is enforced separately by the resource).
  """
  @callback validate(value :: term, config :: map) :: :ok | {:error, String.t()}

  @doc "The default value for a new record's field, given its `config`."
  @callback default(config :: map) :: term

  @doc """
  Cast raw input (e.g. from an MCP/JSON payload or a form) into the stored
  representation. Returns `{:ok, cast}` or `{:error, message}`.
  """
  @callback cast(input :: term, config :: map) :: {:ok, term} | {:error, String.t()}

  @doc """
  A JSON-schema fragment describing this field's value, used by the MCP
  `ToolProjector` to build typed tool parameters. Map with string keys
  (e.g. `%{"type" => "number"}`).
  """
  @callback json_schema(config :: map) :: map

  @doc "Whether this field's values live in `RecordLink` rows (relations)."
  @callback relational?() :: boolean

  # ── presentation contract (the object-layer analogue of BlockType render) ──
  #
  # These make every human surface (board card, record detail, record_ref
  # badge) and the ObjectType/FieldDef editor *generic projectors* over the
  # registry: a dispatcher routes on `field_type`, never branches per type.
  # See docs/objects_and_tasks_ux.md §1.

  @doc "Emoji/icon for type pickers and field rows."
  @callback icon() :: String.t()

  @doc """
  Read-only display of a stored `value` (card pill, detail row, record_ref
  badge). `assigns` carries ambient context (e.g. `:members` for `:user`,
  `:linked` records for `:relation`) so the component stays pure.
  """
  @callback render_value(value :: term, config :: map, assigns :: map) ::
              Phoenix.LiveView.Rendered.t()

  @doc """
  The edit control for this field (record detail, create form). `field` is a
  `Phoenix.HTML.FormField`; `assigns` carries context (members, link options).
  """
  @callback render_input(field :: Phoenix.HTML.FormField.t(), config :: map, assigns :: map) ::
              Phoenix.LiveView.Rendered.t()

  @doc """
  The field's own settings UI in the ObjectType/FieldDef editor (e.g.
  `:select` edits its option list). Optional — most types have no config.
  """
  @callback render_config_form(config :: map, form :: Phoenix.HTML.Form.t()) ::
              Phoenix.LiveView.Rendered.t()

  @optional_callbacks relational?: 0, render_config_form: 2
end
