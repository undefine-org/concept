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
    defaults [:read, :destroy]

    create :create_personal do
      accept [:name, :slug, :icon_emoji, :owner_id, :primary?]
    end

    update :rename do
      accept [:name]
    end

    update :set_icon do
      accept [:icon_emoji]
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(memberships.user_id == ^arg(:user_id))
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
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
