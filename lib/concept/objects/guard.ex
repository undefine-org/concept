defmodule Concept.Objects.Guard do
  @moduledoc """
  Behaviour each transition guard implements — the *developer plane* of the
  validation engine. A guard is a reusable rule that must pass before a record
  may move along a transition (e.g. "requires approval by the creator",
  "requires a linked PR", "checklist must be complete").

  Guards are registered in `:concept, :record_guards` and composed *per
  transition* as data: a `Transition` row carries
  `guards: [%{"kind" => "requires_approval", "config" => %{...}}, ...]`.
  The `Concept.Objects.Record.Changes.RunTransition` engine resolves each
  `kind` to its module and calls `check/3`.

  `describe/1` keeps a composed guard legible to the workflow editor UI and to
  MCP agents (it feeds the per-type transition tool descriptions).
  """

  @typedoc "Registry key, e.g. `:requires_approval`."
  @type kind :: atom

  @typedoc """
  Context passed to a guard check:
    * `:record`   — the record being transitioned (with `fields`, `created_by_id`, …)
    * `:actor`    — the actor performing the transition
    * `:to_state` — the target `WorkflowState`
    * `:tenant`   — workspace id
  """
  @type context :: %{
          optional(:record) => map,
          optional(:actor) => map | nil,
          optional(:to_state) => map,
          optional(:tenant) => String.t() | nil
        }

  @doc "The atom key this guard registers under."
  @callback kind() :: kind

  @doc "Human label for the workflow-editor guard palette."
  @callback label() :: String.t()

  @doc """
  Check the guard against a record + config + context.
  Returns `:ok` to allow the transition, or `{:error, reason}` to block it.
  """
  @callback check(record :: map, config :: map, context :: context) ::
              :ok | {:error, String.t()}

  @doc "A one-line description of this guard instance, given its config."
  @callback describe(config :: map) :: String.t()

  @doc "Emoji/icon for the workflow-editor guard palette."
  @callback icon() :: String.t()

  @doc """
  The guard's config-editing UI in the workflow editor's guard palette
  (e.g. `requires_proof` picks which field is the proof). Optional — a guard
  with no config (none currently) may omit it. Mirrors
  `FieldType.render_config_form/2`.
  """
  @callback render_config_form(config :: map, form :: Phoenix.HTML.Form.t()) ::
              Phoenix.LiveView.Rendered.t()

  @doc """
  Normalize raw config params (as submitted by `render_config_form/2`) into
  the stored/queried shape (as consumed by `check/3` and `describe/1`).
  E.g. `requires_fields` turns a comma-string into a list. Optional — defaults
  to identity. The guard owns its config shape end to end.
  """
  @callback normalize_config(raw :: map) :: map

  @optional_callbacks render_config_form: 2, normalize_config: 1
end
