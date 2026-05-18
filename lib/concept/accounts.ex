defmodule Concept.Accounts do
  @moduledoc "Identity & tenancy: User, Token, Workspace, Membership."
  use Ash.Domain,
    otp_app: :concept,
    extensions: [AshAdmin.Domain, AshAi, Concept.AutoTools]

  admin do
    show? true
  end

  require Ash.Query

  mcp_resources do
    mcp_resource :my_workspaces,
                 "concept://me/workspaces",
                 Concept.Accounts.Workspace,
                 :my_workspaces_json,
                 title: "My Workspaces",
                 description: "Workspaces the actor is a member of.",
                 mime_type: "application/json"
  end

  resources do
    resource Concept.Accounts.Token
    resource Concept.Accounts.User
    resource Concept.Accounts.Workspace
    resource Concept.Accounts.Membership
    resource Concept.Accounts.ApiKey
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

  @doc """
  Returns the authenticated user's primary workspace.

  Falls back to the oldest membership workspace when no primary is set.
  """
  def get_primary_workspace(user, opts \\ []) do
    actor = opts[:actor] || user

    primary_query =
      Concept.Accounts.Workspace
      |> Ash.Query.filter(memberships.user_id == ^user.id and primary? == true)

    case Ash.read_one(primary_query, actor: actor, authorize?: true) do
      {:ok, %{} = ws} ->
        {:ok, ws}

      {:ok, nil} ->
        Concept.Accounts.Workspace
        |> Ash.Query.filter(memberships.user_id == ^user.id)
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.Query.limit(1)
        |> Ash.read_one(actor: actor, authorize?: true)

      {:error, _} = err ->
        err
    end
  end
end
