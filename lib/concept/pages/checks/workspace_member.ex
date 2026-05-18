defmodule Concept.Pages.Checks.WorkspaceMember do
  @moduledoc """
  Authorizes when the actor is a member of the subject's tenant workspace.

  Implemented as an `Ash.Policy.FilterCheck` so the membership predicate is
  fused into the action's main SQL (an `EXISTS` subquery on the
  `workspace_memberships` relationship), instead of issuing a separate
  `SELECT … FROM memberships LIMIT 1` per policy evaluation.

  Resources using this check must declare a `:workspace_memberships`
  relationship to `Concept.Accounts.Membership` filtered by
  `workspace_id == parent(workspace_id)` (see
  `Concept.Pages.Block` and `Concept.Pages.Page`).
  """
  use Ash.Policy.FilterCheck
  require Ash.Expr

  @impl true
  def describe(_), do: "actor is a member of the workspace"

  @impl true
  def filter(_actor, _authorizer, _opts) do
    Ash.Expr.expr(exists(workspace_memberships, user_id == ^actor(:id)))
  end
end
