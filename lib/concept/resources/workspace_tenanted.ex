defmodule Concept.Resources.WorkspaceTenanted do
  @moduledoc """
  Declares a resource as workspace-tenanted.

  Hoists the four-block recipe that previously sprawled across six
  resources (`Block`, `Page`, `Knowledge.Link`, `Knowledge.Citation`,
  `Knowledge.TokenLedger`, `Knowledge.IngestionJob`):

    * `multitenancy strategy :attribute, attribute: :workspace_id, global? false`
    * `has_many :workspace_memberships` filtered by parent `workspace_id` —
      drives `Concept.Pages.Checks.WorkspaceMember` (a `FilterCheck`) so the
      `EXISTS` subquery fuses into the action's main SQL instead of issuing
      a separate `SELECT … FROM memberships` per policy evaluation.
    * Policy floor: a system-actor bypass and a `:read` authorization gated
      by `WorkspaceMember`.

  ## Usage

      defmodule Concept.Pages.Block do
        use Concept.Resources.WorkspaceTenanted,
          otp_app: :concept,
          domain: Concept.Pages,
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer],
          extensions: [AshArchival.Resource, AshStateMachine, AshOban],
          notifiers: [Ash.Notifier.PubSub, Concept.Pages.Notifiers.KnowledgeReindex]

        # …everything else, *minus* the multitenancy block, the
        # workspace_memberships relationship, and the read-by-member policy.
        # Add resource-specific create/update/destroy policies as needed.
      end

  ## Per-resource policies

  This module injects only the policies common to every workspace-tenanted
  resource. Resources still own their write-side policies. Two additional
  Ash `policies do` blocks aggregate cleanly with the one injected here.

  Conventions for the resource's own `policies` block:

    * `:create` actions where members may write: use
      `Concept.Pages.Checks.WorkspaceMemberCreate` (a `SimpleCheck`;
      `FilterCheck` cannot authorize a row that does not yet exist).
    * `:update` / `:destroy` actions where members may write: use
      `Concept.Pages.Checks.WorkspaceMember`.
    * System-only writes: `authorize_if actor_attribute_equals(:system?, true)`.
  """

  defmacro __using__(opts) do
    # `Macro.var(:workspace_id, nil)` produces a context-less identifier so
    # `Ash.Expr.expr/1` interprets it as a field reference (the default for
    # bare atoms in filter DSL) instead of a hygiene-tagged variable in the
    # extension module's context.
    ws_id = Macro.var(:workspace_id, nil)

    quote do
      use Ash.Resource, unquote(opts)

      multitenancy do
        strategy :attribute
        attribute :workspace_id
        global? false
      end

      relationships do
        # Drives `Concept.Pages.Checks.WorkspaceMember` (FilterCheck). The
        # `EXISTS` subquery rides on the action's main SQL instead of firing
        # a separate `SELECT … FROM memberships` per policy evaluation.
        has_many :workspace_memberships, Concept.Accounts.Membership,
          no_attributes?: true,
          filter: expr(unquote(ws_id) == parent(unquote(ws_id)))
      end

      policies do
        bypass actor_attribute_equals(:system?, true) do
          authorize_if always()
        end

        policy action_type(:read) do
          authorize_if Concept.Pages.Checks.WorkspaceMember
        end
      end
    end
  end
end
