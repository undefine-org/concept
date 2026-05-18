defmodule Concept.AutoToolsFixtures.FixtureDomain do
  @moduledoc false
  use Ash.Domain, extensions: [AshAi, Concept.AutoTools]

  resources do
    resource Concept.AutoToolsFixtures.FixtureResource
  end
end
