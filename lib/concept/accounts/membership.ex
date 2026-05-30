defmodule Concept.Accounts.Membership do
  @moduledoc "Joins a User to a Workspace with a role (`:owner` | `:member`)."
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Concept.Repo

    references do
      reference :workspace, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :create, args: [:workspace_id, :user_id, :role]
    define :update_role, args: [:role]
    define :list_for_workspace, action: :for_workspace, args: [:workspace_id]
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      description "List the actor's workspace memberships."
    end

    read :for_workspace do
      description "List all memberships (members) of a workspace."

      argument :workspace_id, :uuid,
        allow_nil?: false,
        description: "Workspace whose members to list."

      filter expr(workspace_id == ^arg(:workspace_id))
    end

    create :create do
      description "Add a user to a workspace with a given role."
      accept [:workspace_id, :user_id, :role]
    end

    update :update_role do
      description "Change a member's role in the workspace."
      accept [:role]
      require_atomic? false

      change Concept.Accounts.Membership.Changes.ValidateRoleChange
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id)))
    end

    policy action(:update_role) do
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id) and role in [:owner, :admin]))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id) and role == :owner))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom,
      constraints: [one_of: [:owner, :admin, :member, :agent]],
      default: :member,
      public?: true

    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workspace, Concept.Accounts.Workspace,
      attribute_writable?: true,
      source_attribute: :workspace_id

    belongs_to :user, Concept.Accounts.User, attribute_writable?: true, source_attribute: :user_id
  end

  identities do
    identity :unique_user_workspace, [:workspace_id, :user_id]
  end

  defmodule Changes.ValidateRoleChange do
    @moduledoc """
    Prevents privilege escalation and owner lockout on membership role changes.
    Only an owner may change another owner's role or promote someone to owner.
    The last owner cannot be demoted.
    """
    use Ash.Resource.Change
    require Ash.Query

    @impl true
    def change(changeset, _opts, ctx) do
      Ash.Changeset.before_action(changeset, &validate(&1, ctx.actor))
    end

    defp validate(changeset, actor) do
      current_role = changeset.data.role
      workspace_id = changeset.data.workspace_id
      new_role = Ash.Changeset.get_attribute(changeset, :role)

      cond do
        is_nil(actor) ->
          changeset

        current_role == :owner and not actor_owner?(actor, workspace_id) ->
          Ash.Changeset.add_error(changeset, field: :role, message: "only an owner may change an owner's role")

        new_role == :owner and not actor_owner?(actor, workspace_id) ->
          Ash.Changeset.add_error(changeset, field: :role, message: "only an owner may promote to owner")

        current_role == :owner and new_role != :owner and last_owner?(workspace_id) ->
          Ash.Changeset.add_error(changeset, field: :role, message: "cannot demote the last owner")

        true ->
          changeset
      end
    end

    defp actor_owner?(actor, workspace_id) do
      actor_id = actor.id

      Concept.Accounts.Membership
      |> Ash.Query.filter(workspace_id == ^workspace_id and user_id == ^actor_id and role == :owner)
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} -> false
        {:ok, _} -> true
        _ -> false
      end
    end

    defp last_owner?(workspace_id) do
      Concept.Accounts.Membership
      |> Ash.Query.filter(workspace_id == ^workspace_id and role == :owner)
      |> Ash.Query.limit(2)
      |> Ash.read(authorize?: false)
      |> case do
        {:ok, owners} when length(owners) == 1 -> true
        _ -> false
      end
    end
  end
end