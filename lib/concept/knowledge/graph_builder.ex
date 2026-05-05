defmodule Concept.Knowledge.GraphBuilder do
  @moduledoc """
  Structural GraphRAG: builds entities + relationships from Concept's page/block tree.
  Writes directly to Arcana.Graph schemas (pinned to ~> 2.0).
  """

  import Ecto.Query
  alias Concept.Knowledge.SystemActor

  @doc """
  Upserts graph entities and relationships for a page and its blocks.
  Called after chunk ingestion.
  """
  def upsert_page_graph(page, blocks, collection_id, workspace_id) do
    _actor = %SystemActor{system?: true}

    # Upsert page entity
    upsert_entity(%{
      kind: "page",
      name: page.title || "Untitled",
      source_id: "page:#{page.id}",
      collection_id: collection_id,
      metadata: %{page_id: page.id, workspace_id: workspace_id}
    })

    # Upsert block entities + HAS_TYPE relationships
    Enum.each(blocks, fn block ->
      block_name = "#{block.type}: #{String.slice(Concept.Lexical.plain_text(block.content || %{}), 0, 80)}"

      upsert_entity(%{
        kind: "block",
        name: block_name,
        source_id: "block:#{block.id}",
        collection_id: collection_id,
        metadata: %{block_id: block.id, page_id: block.page_id, block_type: to_string(block.type)}
      })

      # Block HAS_TYPE BlockType
      upsert_relationship(%{
        source_id: "block:#{block.id}",
        target_id: "block_type:#{block.type}",
        kind: "HAS_TYPE",
        collection_id: collection_id
      })
    end)

    # CONTAINS: page -> top-level blocks
    top_blocks = Enum.filter(blocks, &is_nil(&1.parent_block_id))
    Enum.each(top_blocks, fn block ->
      upsert_relationship(%{
        source_id: "page:#{page.id}",
        target_id: "block:#{block.id}",
        kind: "CONTAINS",
        collection_id: collection_id
      })
    end)

    # PARENT_OF: block -> child blocks
    child_blocks = Enum.filter(blocks, &(&1.parent_block_id != nil))
    Enum.each(child_blocks, fn block ->
      upsert_relationship(%{
        source_id: "block:#{block.parent_block_id}",
        target_id: "block:#{block.id}",
        kind: "PARENT_OF",
        collection_id: collection_id
      })
    end)

    {:ok, %{entities: 1 + length(blocks), relationships: length(blocks) + length(top_blocks) + length(child_blocks)}}
  end

  @doc """
  Removes all graph entities and relationships for a page.
  """
  def delete_page_graph(page_id, collection_id) do
    Arcana.Graph.Entity
    |> where(collection_id: ^collection_id, source_id: ^"page:#{page_id}")
    |> Concept.Repo.delete_all()

    Arcana.Graph.Entity
    |> where([e], like(e.source_id, ^"block:%"))
    |> where([e], fragment("metadata->>'page_id' = ?", ^to_string(page_id)))
    |> Concept.Repo.delete_all()

    # Relationships cascade via FK or are cleaned up separately
    # (Arcana handles this internally on document delete)
    :ok
  end

  @doc """
  Full rebuild of the workspace graph from all pages.
  """
  def rebuild_workspace_graph(workspace_id) do
    actor = %SystemActor{system?: true}
    collection = Concept.Knowledge.Collections.ensure_for_workspace(workspace_id)

    pages = Concept.Pages.Page
    |> Ash.read!(actor: actor, tenant: workspace_id)

    blocks = Concept.Pages.Block
    |> Ash.read!(actor: actor, tenant: workspace_id)

    blocks_by_page = Enum.group_by(blocks, &(&1.page_id))

    results = Enum.map(pages, fn page ->
      page_blocks = Map.get(blocks_by_page, page.id, [])
      upsert_page_graph(page, page_blocks, collection.id, workspace_id)
    end)

    total_entities = Enum.sum(Enum.map(results, fn {:ok, r} -> r.entities end))
    total_relationships = Enum.sum(Enum.map(results, fn {:ok, r} -> r.relationships end))

    {:ok, %{entities: total_entities, relationships: total_relationships}}
  end

  defp upsert_entity(attrs) do
    Arcana.Graph.Entity
    |> where(collection_id: ^attrs.collection_id, kind: ^attrs.kind, source_id: ^attrs.source_id)
    |> Concept.Repo.one()
    |> case do
      nil ->
        %Arcana.Graph.Entity{}
        |> Arcana.Graph.Entity.changeset(attrs)
        |> Concept.Repo.insert!()
      existing ->
        existing
        |> Arcana.Graph.Entity.changeset(attrs)
        |> Concept.Repo.update!()
    end
  end

  defp upsert_relationship(attrs) do
    Arcana.Graph.Relationship
    |> where(collection_id: ^attrs.collection_id, source_id: ^attrs.source_id, target_id: ^attrs.target_id, kind: ^attrs.kind)
    |> Concept.Repo.one()
    |> case do
      nil ->
        %Arcana.Graph.Relationship{}
        |> Arcana.Graph.Relationship.changeset(attrs)
        |> Concept.Repo.insert!()
      existing ->
        existing
        |> Arcana.Graph.Relationship.changeset(attrs)
        |> Concept.Repo.update!()
    end
  end
end
