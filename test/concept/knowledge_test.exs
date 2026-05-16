defmodule Concept.KnowledgeTest do
  use ExUnit.Case, async: true

  describe "domain registration" do
    test "Concept.Knowledge is in the ash_domains config" do
      assert Concept.Knowledge in Application.fetch_env!(:concept, :ash_domains)
    end

    test "domain module loaded" do
      assert Code.ensure_loaded?(Concept.Knowledge)
    end

    test "domain has expected knowledge resources" do
      resources = Ash.Domain.Info.resources(Concept.Knowledge)

      assert Concept.Knowledge.IngestionJob in resources
      assert Concept.Knowledge.Citation in resources
      assert Concept.Knowledge.Link in resources
      assert Concept.Knowledge.Link.Version in resources
      assert Concept.Knowledge.TokenLedger in resources
      assert Concept.Knowledge.Tools in resources

      # Ensure we have exactly these 6 resources
      assert length(resources) == 6
    end
  end
end
