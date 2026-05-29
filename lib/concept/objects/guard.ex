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
end
