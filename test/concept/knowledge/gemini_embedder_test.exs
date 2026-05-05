defmodule Concept.Knowledge.GeminiEmbedderTest do
  use ExUnit.Case, async: true

  alias Concept.Knowledge.GeminiEmbedder

  describe "dimensions/1" do
    test "returns 768 regardless of opts" do
      assert GeminiEmbedder.dimensions([]) == 768
      assert GeminiEmbedder.dimensions(model: "other") == 768
    end
  end

  describe "embed/2" do
    test "with intent: :document sends RETRIEVAL_DOCUMENT taskType" do
      req = GeminiEmbedder.__send_for_test__("test", :document)
      assert req.taskType == "RETRIEVAL_DOCUMENT"
    end

    test "with intent: :query sends RETRIEVAL_QUERY" do
      req = GeminiEmbedder.__send_for_test__("test", :query)
      assert req.taskType == "RETRIEVAL_QUERY"
    end

    test "with no intent omits taskType" do
      req = GeminiEmbedder.__send_for_test__("test", nil)
      refute Map.has_key?(req, :taskType)
    end
  end
end