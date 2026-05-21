defmodule Concept.Accounts.ApiKey do
  use Ash.Resource,
    otp_app: :concept,
    domain: Concept.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo Concept.Repo
  end

  actions do
    read :read do
      primary? true

      description "List the actor's API keys (hashes only; key material is shown only at creation)."
    end

    destroy :destroy do
      primary? true
      description "Revoke an API key by id."
    end

    create :create do
      primary? true
      description "Issue an API key for the actor; optionally bind it to a single workspace."

      accept [:user_id, :expires_at, :workspace_id]

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey,
              prefix: :concept, hash: :api_key_hash}
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :workspace_id, :uuid do
      allow_nil? true
      public? true
      description "If set, this API key authorizes only the bound workspace."
    end
  end

  relationships do
    belongs_to :user, Concept.Accounts.User

    belongs_to :workspace, Concept.Accounts.Workspace,
      attribute_writable?: false,
      source_attribute: :workspace_id
  end

  calculations do
    calculate :valid, :boolean, expr(expires_at > now())
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end
end
