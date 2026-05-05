defmodule Concept.KnowledgeTest do
  use ExUnit.Case, async: true

  describe "domain registration" do
    test "Concept.Knowledge is in the ash_domains config" do
      assert Concept.Knowledge in Application.fetch_env!(:concept, :ash_domains)
    end

    test "domain module loaded" do
      assert Code.ensure_loaded?(Concept.Knowledge)
    end

    test "domain has no resources" do
      assert Ash.Domain.Info.resources(Concept.Knowledge) == []
    end
  end
end
