defmodule Concept.AutoToolsFixtures.FixtureDomain do
  @moduledoc false
  # `validate_config_inclusion?: false` — fixture domains are test-only and
  # intentionally absent from `config :concept, :ash_domains`.
  use Ash.Domain,
    extensions: [AshAi, Concept.AutoTools],
    validate_config_inclusion?: false

  resources do
    resource Concept.AutoToolsFixtures.FixtureResource
  end
end
