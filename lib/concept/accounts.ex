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

  @doc """
  Resolve a bounded list of users by id for *display* (avatars, member
  pickers). The `User` read policy is self-only, so this performs a bounded,
  unauthorized read — callers MUST have already authorized access to the set
  of ids (e.g. by reading the workspace's memberships as the actor). Keeping
  the escalation here (not in a LiveView) makes it auditable in one place.
  """
  def list_users_by_ids([]), do: {:ok, []}

  def list_users_by_ids(ids) when is_list(ids) do
    Concept.Accounts.User
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read(authorize?: false)
  end

  @doc """
  List members of a workspace with their user record loaded.
  """
  def list_members(workspace_id, opts \\ []) do
    actor = opts[:actor]

    with {:ok, memberships} <-
           Concept.Accounts.Membership
           |> Ash.Query.filter(workspace_id == ^workspace_id)
           |> Ash.read(actor: actor, authorize?: true),
         {:ok, memberships} <-
           Ash.load(memberships, :user, authorize?: false) do
      {:ok, memberships}
    end
  end

  @doc """
  Add an existing user to a workspace by email.

  Returns `{:ok, membership}` on success, `{:error, :user_not_found}`
  if no user has that email, or `{:error, :already_member}` if the
  user is already a member of the workspace.
  """
  def add_member(workspace_id, email, opts \\ []) do
    actor = opts[:actor]

    case Concept.Accounts.User
         |> Ash.Query.filter(email == ^email)
         |> Ash.read_one(actor: actor, authorize?: false) do
      {:ok, nil} ->
        {:error, :user_not_found}

      {:error, reason} ->
        {:error, reason}

      {:ok, user} ->
        case get_membership(user.id, workspace_id, actor: actor) do
          {:ok, %Concept.Accounts.Membership{}} ->
            {:error, :already_member}

          {:ok, nil} ->
            Concept.Accounts.Membership.create(
              workspace_id,
              user.id,
              :member,
              actor: actor
            )

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Change a member's role in a workspace.

  `role` must be one of the Membership role enum values.
  """
  def set_member_role(membership, role, opts \\ []) do
    actor = opts[:actor]

    membership
    |> Ash.Changeset.for_update(:update_role, %{role: role})
    |> Ash.update(actor: actor, authorize?: true)
  end

  @doc """
  List API keys bound to a workspace (hashes only; no plaintext).
  """
  def list_api_keys(workspace_id, opts \\ []) do
    actor = opts[:actor]

    Concept.Accounts.ApiKey.for_workspace(workspace_id, actor: actor)
  end

  @doc """
  Issue a workspace-bound API key for the actor.

  Returns `{:ok, %{api_key: key_struct, plaintext: "..."}}`.
  The plaintext is available only at creation time.
  """
  def issue_api_key(workspace_id, attrs, opts \\ []) do
    actor = opts[:actor]

    expires_at = attrs[:expires_at] || DateTime.add(DateTime.utc_now(), 365, :day)

    case Concept.Accounts.ApiKey.create(
           actor.id,
           expires_at,
           workspace_id,
           actor: actor
         ) do
      {:ok, api_key} ->
        plaintext = api_key.__metadata__.plaintext_api_key
        {:ok, %{api_key: api_key, plaintext: plaintext}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Revoke (destroy) an API key.
  """
  def revoke_api_key(api_key, opts \\ []) do
    actor = opts[:actor]

    Ash.destroy(api_key, actor: actor, authorize?: true)
  end
end
