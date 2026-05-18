defmodule Concept.Accounts.Workspace do
  @moduledoc """
  A workspace owns a tree of pages. Every user gets a personal workspace
  on signup (Reactor: `Concept.Accounts.Reactors.Onboarding`).
  """
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo Concept.Repo
  end

  code_interface do
    define :create_personal, args: [:name, :slug, :icon_emoji, :owner_id]
    define :for_user, args: [:user_id]
    define :by_slug, args: [:slug]
    define :rename, args: [:name]
    define :set_icon, args: [:icon_emoji]
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      description "Read a workspace by id."
    end

    create :create_personal do
      accept [:name, :slug, :icon_emoji, :owner_id, :primary?]
    end

    update :rename do
      description "Rename a workspace."
      accept [:name]
    end

    update :set_icon do
      description "Set a workspace's icon emoji."
      accept [:icon_emoji]
    end

    read :for_user do
      description "List workspaces a user is a member of."

      argument :user_id, :uuid,
        allow_nil?: false,
        description: "User whose memberships to list."

      filter expr(memberships.user_id == ^arg(:user_id))
    end

    read :by_slug do
      description "Read a workspace by its URL slug."

      argument :slug, :string,
        allow_nil?: false,
        description: "Workspace slug from the URL path."

      get? true
      filter expr(slug == ^arg(:slug))
    end

    action :my_workspaces_json, :string do
      description "List the actor's workspaces as a JSON array. Used as an MCP resource at concept://me/workspaces."

      run fn _input, ctx ->
        actor = ctx.actor

        if is_nil(actor) do
          {:error, "actor required"}
        else
          require Ash.Query

          query =
            Concept.Accounts.Workspace
            |> Ash.Query.filter(memberships.user_id == ^actor.id)

          case Ash.read(query, actor: actor, authorize?: true) do
            {:ok, workspaces} ->
              payload =
                Enum.map(workspaces, fn ws ->
                  %{id: ws.id, name: ws.name, slug: ws.slug, icon_emoji: ws.icon_emoji}
                end)

              Jason.encode(payload)

            {:error, e} ->
              {:error, e}
          end
        end
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:system?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(memberships.user_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and role == :owner))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :icon_emoji, :string, default: "🏠", public?: true
    attribute :owner_id, :uuid, allow_nil?: false, public?: true
    attribute :primary?, :boolean, default: false, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Concept.Accounts.User,
      attribute_writable?: true,
      source_attribute: :owner_id

    has_many :memberships, Concept.Accounts.Membership
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
