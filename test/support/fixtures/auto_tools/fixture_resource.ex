defmodule Concept.AutoToolsFixtures.FixtureResource do
  @moduledoc false
  # Plain (non-embedded) Ash resource so the fixture domain can list it in
  # its `resources do` block without tripping the Ash validator ("Embedded
  # resources should not be listed in the domain"). The auto_tools test
  # only exercises action metadata, never CRUD, so the default in-memory
  # data layer suffices.
  use Ash.Resource, domain: Concept.AutoToolsFixtures.FixtureDomain

  actions do
    defaults [:read]

    # Described — should be auto-exposed.
    read :described_read do
      description "Fixture read action with a description."
      argument :query, :string, allow_nil?: false, description: "Query string."
    end

    # Undescribed — should NOT be auto-exposed.
    read :silent_read do
    end

    # Generic action — described, should be auto-exposed.
    action :described_generic, :map do
      description "Fixture generic action with a description."
      argument :payload, :map, allow_nil?: true, description: "Payload."

      run fn _input, _ctx -> {:ok, %{}} end
    end

    # Excluded via app config — should NOT be auto-exposed.
    read :excluded_read do
      description "This action is excluded via the global deny list."
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end
