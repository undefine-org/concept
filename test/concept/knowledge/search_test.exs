defmodule Concept.Knowledge.SearchTest do
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Search

  @workspace_id "ws_test_#{System.unique_integer([:positive])}"
  @collection_name Concept.Knowledge.Config.collection_for(@workspace_id)

  # Simple chunker for tests that splits on double newline
  defmodule SimpleChunker do
    @behaviour Arcana.Chunker

    @impl true
    def chunk(text, opts) do
      metadata = Keyword.get(opts, :metadata, %{})

      text
      |> String.split("\n\n", trim: true)
      |> Enum.with_index()
      |> Enum.map(fn {chunk_text, idx} ->
        %{
          text: String.trim(chunk_text),
          chunk_index: idx,
          token_count: div(byte_size(chunk_text), 4),
          metadata: metadata
        }
      end)
    end
  end

  describe "search/3" do
    test "returns empty list when collection does not exist" do
      assert {:ok, []} = Search.search("anything", "nonexistent_workspace_#{:rand.uniform(999_999)}")
    end

    test "returns empty list for empty collection" do
      # Create collection but don't ingest anything
      {:ok, _collection} = Arcana.Collection.get_or_create(@collection_name, Concept.Repo)

      assert {:ok, []} = Search.search("test query", @workspace_id)
    end

    test "returns hits with normalized metadata shape after ingestion" do
      # Ensure collection exists
      {:ok, _collection} = Arcana.Collection.get_or_create(@collection_name, Concept.Repo)

      # Ingest a test document with metadata
      text = """
      This is a test document about Phoenix and Elixir.
      It contains information about web development.
      """

      metadata = %{
        "block_id" => "block_123",
        "page_id" => "page_456",
        "breadcrumbs" => ["Docs", "Guides", "Phoenix"],
        "block_type" => "paragraph"
      }

      assert {:ok, _} =
               Arcana.ingest(text,
                 repo: Concept.Repo,
                 collection: @collection_name,
                 metadata: metadata,
                 chunker: SimpleChunker
               )

      # Search with keyword mode for exact match
      assert {:ok, hits} = Search.search("Phoenix", @workspace_id, limit: 5, mode: :keyword)
      assert length(hits) >= 1, "Expected at least 1 hit but got #{length(hits)}"

      # Verify normalized shape
      hit = List.first(hits)
      assert is_map(hit)
      assert Map.has_key?(hit, :block_id)
      assert Map.has_key?(hit, :page_id)
      assert Map.has_key?(hit, :breadcrumbs)
      assert Map.has_key?(hit, :snippet)
      assert Map.has_key?(hit, :score)
      assert Map.has_key?(hit, :rank)
      assert Map.has_key?(hit, :chunk_id)

      # Verify metadata values
      assert hit.block_id == "block_123"
      assert hit.page_id == "page_456"
      assert hit.breadcrumbs == ["Docs", "Guides", "Phoenix"]
      assert is_binary(hit.snippet)
      assert hit.score > 0
      assert hit.rank == 1
    end

    test "metadata uses string keys and handles missing fields gracefully" do
      collection_name = Concept.Knowledge.Config.collection_for("ws_string_keys_#{:rand.uniform(999_999)}")
      {:ok, _collection} = Arcana.Collection.get_or_create(collection_name, Concept.Repo)

      # Ingest document with partial metadata
      text = "Content without full metadata"
      metadata = %{"page_id" => "page_789"}

      assert {:ok, _} =
               Arcana.ingest(text,
                 repo: Concept.Repo,
                 collection: collection_name,
                 metadata: metadata,
                 chunker: SimpleChunker
               )

      workspace_id = String.replace_prefix(collection_name, "workspace:", "")
      # Use keyword mode for exact match
      assert {:ok, hits} = Search.search("Content", workspace_id, mode: :keyword)
      assert length(hits) >= 1, "Expected at least 1 hit for 'Content'"
      hit = List.first(hits)

      # Should not raise on missing keys
      assert hit.page_id == "page_789"
      assert hit.block_id == nil
      assert hit.breadcrumbs == nil

      # Should not use String.to_existing_atom (would raise on unknown keys)
      assert is_nil(hit.block_id) or is_binary(hit.block_id)
    end
  end

  describe "search modes" do
    setup do
      collection_name = Concept.Knowledge.Config.collection_for("ws_modes_#{:rand.uniform(999_999)}")
      {:ok, _collection} = Arcana.Collection.get_or_create(collection_name, Concept.Repo)

      text = "Elixir is a functional programming language"
      metadata = %{"block_id" => "test_block"}

      {:ok, _} =
        Arcana.ingest(text,
          repo: Concept.Repo,
          collection: collection_name,
          metadata: metadata,
          chunker: SimpleChunker
        )

      workspace_id = String.replace_prefix(collection_name, "workspace:", "")
      {:ok, workspace_id: workspace_id}
    end

    test "supports hybrid mode", %{workspace_id: workspace_id} do
      assert {:ok, hits} = Search.search("Elixir", workspace_id, mode: :hybrid)
      assert length(hits) >= 1
    end

    test "supports semantic mode", %{workspace_id: workspace_id} do
      assert {:ok, hits} = Search.search("functional language", workspace_id, mode: :semantic)
      assert is_list(hits)
    end

    test "supports keyword mode", %{workspace_id: workspace_id} do
      assert {:ok, hits} = Search.search("Elixir", workspace_id, mode: :keyword)
      assert is_list(hits)
    end
  end
end
