defmodule Concept.AutoToolsFixtures.FixtureDomainWithManualTool do
  @moduledoc false
  use Ash.Domain, extensions: [AshAi, Concept.AutoTools]

  # This manual entry collides with the name AutoTools would synthesize for
  # `FixtureResource :described_read` (`:fixture_resource_described_read`).
  # The manual entry must win; AutoTools must emit a Logger.warning/1.
  tools do
    tool :fixture_resource_described_read,
         Concept.AutoToolsFixtures.FixtureResource,
         :described_read do
      description "Manual override — takes precedence over auto-synthesis."
    end
  end

  resources do
    resource Concept.AutoToolsFixtures.FixtureResource
  end
end
