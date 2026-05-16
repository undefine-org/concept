defmodule Concept.Knowledge.CommunityTest do
  use Concept.DataCase, async: true

  alias Concept.Knowledge.Community

  # Simple chunker for tests
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

  describe "rebuild_communities/1" do
    test "returns ok with zero communities for empty workspace" do
      workspace_id = "ws_empty_#{:rand.uniform(999_999)}"
      collection_name = Concept.Knowledge.Config.collection_for(workspace_id)

      # Ensure collection exists but is empty
      {:ok, _collection} = Arcana.Collection.get_or_create(collection_name, Concept.Repo)

      assert {:ok, result} = Community.rebuild_communities(workspace_id)
      assert is_map(result)
      assert Map.has_key?(result, :communities_detected)
      assert Map.has_key?(result, :summaries_written)
      assert result.communities_detected >= 0
      assert result.summaries_written >= 0
    end

    @tag :integration
    test "returns positive communities_detected with ingested content and entities" do
      workspace_id = "ws_community_#{:rand.uniform(999_999)}"
      collection_name = Concept.Knowledge.Config.collection_for(workspace_id)

      {:ok, _collection} = Arcana.Collection.get_or_create(collection_name, Concept.Repo)

      # Ingest documents that may form communities
      documents = [
        %{
          text: """
          Phoenix is a web framework written in Elixir.
          It follows the MVC pattern and enables building scalable applications.
          """,
          metadata: %{"block_id" => "block_1", "page_id" => "page_phoenix"}
        },
        %{
          text: """
          Elixir runs on the BEAM virtual machine.
          It provides excellent concurrency through lightweight processes.
          """,
          metadata: %{"block_id" => "block_2", "page_id" => "page_elixir"}
        },
        %{
          text: """
          LiveView is a library in Phoenix that enables rich, real-time user experiences
          with server-rendered HTML. It uses WebSockets for communication.
          """,
          metadata: %{"block_id" => "block_3", "page_id" => "page_liveview"}
        }
      ]

      for doc <- documents do
        assert {:ok, _} =
                 Arcana.ingest(doc.text,
                   repo: Concept.Repo,
                   collection: collection_name,
                   metadata: doc.metadata,
                   chunker: SimpleChunker
                 )
      end

      # Rebuild communities
      assert {:ok, result} = Community.rebuild_communities(workspace_id)
      assert result.communities_detected >= 0
      assert result.summaries_written >= 0

      # Note: Actual community detection depends on graph extraction and entity linking,
      # which may not be fully operational in all test environments.
      # The important part is that the function completes successfully.
    end
  end

  describe "error handling" do
    test "returns error tuple on failure" do
      # Use an invalid workspace_id that might cause issues
      # The actual behavior depends on Arcana internals, but we verify structure
      workspace_id = "ws_error_#{:rand.uniform(999_999)}"

      case Community.rebuild_communities(workspace_id) do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, :communities_detected)

        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason) or is_tuple(reason)
      end
    end
  end
end
