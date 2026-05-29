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

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(exists(workspace.memberships, user_id == ^actor(:id) and role == :owner))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom,
      constraints: [one_of: [:owner, :member, :agent]],
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
end
