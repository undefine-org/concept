defmodule Concept.Accounts do
  @moduledoc "Identity & tenancy: User, Token, Workspace, Membership."
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  require Ash.Query

  resources do
    resource Concept.Accounts.Token
    resource Concept.Accounts.User
    resource Concept.Accounts.Workspace
    resource Concept.Accounts.Membership
  end

  @doc """
  Retrieves a single membership for `user_id` in `workspace_id`.

  Returns `{:ok, membership}` when found, `{:ok, nil}` when not found.
  Acts as the official bridge between `Scope.for_user/2` and the
  `Membership` resource — keeping the Ash query logic in one place.
  """
  def get_membership(user_id, workspace_id, opts \\ []) do
    actor = opts[:actor]

    Concept.Accounts.Membership
    |> Ash.Query.filter(user_id: user_id, workspace_id: workspace_id)
    |> Ash.read_one(actor: actor, authorize?: true, load: :workspace)
  end
end
