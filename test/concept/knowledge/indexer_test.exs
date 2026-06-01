defmodule Concept.Knowledge.IndexerTest do
  @moduledoc """
  Regression coverage for the RAG ingest → retrieve → cite round-trip.

  These guard against three Arcana 2.0.0 behaviours that, together, silently
  disabled grounding (every conversation answered ungrounded with zero
  citations) and were invisible to mocked ingest tests:

    * `:chunker_opts` is dropped by `Arcana.Ingest.ingest/2` — chunker inputs
      must ride on a per-call `:chunker` override. Without it BlockChunker
      raised and zero chunks were written.
    * `embed_single_chunk/5` drops each chunk's `:metadata` — the Indexer
      backfills it so citations can attribute hits to a source block/page.
    * the hybrid search path rebuilds hits from a fixed field set and drops
      custom metadata — `Search.search/3` reloads it from the chunk rows.

  Uses the real Arcana pipeline (offline MockEmbedder), not a mock module.
  """
  use Concept.DataCase, async: false

  alias Concept.{Accounts, Knowledge, Pages}
  alias Concept.Knowledge.{Indexer, Search}

  defp fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "indexer_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Grounding Spec", workspace.id, nil, actor: user, tenant: workspace.id)

    %{user: user, workspace: workspace, page: page}
  end

  defp paragraph(text) do
    %{
      "root" => %{
        "type" => "root",
        "children" => [
          %{"type" => "paragraph", "children" => [%{"type" => "text", "text" => text}]}
        ]
      }
    }
  end

  defp add_block(page, ws, user, text) do
    {:ok, block} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block} = Pages.update_content(block, paragraph(text), actor: user, tenant: ws.id)
    block
  end

  describe "ingest_source/4 + Search.search/3" do
    test "persists chunks with embeddings and per-chunk metadata, and hits are citable" do
      %{user: user, workspace: ws, page: page} = fixtures()

      block =
        add_block(
          page,
          ws,
          user,
          "The Zorblax handshake rotates Vexil keys every 37 minutes in the Grimble vault."
        )

      {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)

      assert {:ok, chunk_count} =
               Indexer.ingest_source(ws.id, "page:#{page.id}", page.title,
                 page: page,
                 blocks: blocks,
                 workspace_id: ws.id
               )

      assert chunk_count >= 1

      # Chunk rows exist with embeddings AND the backfilled metadata.
      collection = Knowledge.Config.collection_for(ws.id)

      rows =
        from(c in "arcana_chunks",
          join: d in "arcana_documents",
          on: c.document_id == d.id,
          join: col in "arcana_collections",
          on: d.collection_id == col.id,
          where: col.name == ^collection and d.source_id == ^"page:#{page.id}",
          select: %{has_embedding: not is_nil(c.embedding), metadata: c.metadata}
        )
        |> Concept.Repo.all()

      assert rows != []
      assert Enum.all?(rows, & &1.has_embedding)

      meta = List.first(rows).metadata
      assert meta["page_id"] == page.id
      assert meta["block_id"] == block.id
      assert meta["breadcrumbs"] == page.title

      # Retrieval returns the chunk, and every hit carries the source
      # block_id + page_id so citations are persistable. Keyword mode keeps the
      # match deterministic under the SHA-based offline MockEmbedder (whose
      # vector similarity is intentionally arbitrary).
      assert {:ok, hits} = Search.search("Vexil", ws.id, limit: 5, mode: :keyword)

      assert hits != []
      hit = List.first(hits)
      assert hit.page_id == page.id
      assert hit.block_id == block.id
      assert hit.breadcrumbs == page.title
      assert hit.score > 0
      assert String.contains?(hit.snippet, "Vexil")
    end
  end
end
