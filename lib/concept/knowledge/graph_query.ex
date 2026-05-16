defmodule Concept.Knowledge.GraphQuery do
  @moduledoc """
  Graph data assembly for workspace knowledge graph views.

  Returns pages as nodes, authored/structural relationships as edges,
  and Leiden communities with page-level aggregation.
  """

  import Ecto.Query

  alias Concept.Knowledge.SystemActor

  @type node_t :: %{
          id: Ecto.UUID.t(),
          label: String.t(),
          type: String.t(),
          community_id: Ecto.UUID.t() | nil
        }

  @type edge_t :: %{
          source: Ecto.UUID.t(),
          target: Ecto.UUID.t(),
          kind: atom()
        }

  @type community_t :: %{
          id: Ecto.UUID.t(),
          level: non_neg_integer(),
          summary: String.t(),
          node_ids: [Ecto.UUID.t()]
        }

  @doc """
  Returns nodes, edges, and communities for a workspace graph.

  ## Edge sources
  - Authored: `Concept.Knowledge.Link` rows (block → block)
  - Structural: `Arcana.Graph.Relationship` with type `CONTAINS` or `PARENT_OF`

  Block-level edges are lifted to page-level edges using `block.page_id`.
  Self-loops (page → itself) are dropped.
  """
  @spec graph_for_workspace(Ecto.UUID.t()) :: %{
          nodes: [node_t()],
          edges: [edge_t()],
          communities: [community_t()]
        }
  def graph_for_workspace(workspace_id) do
    actor = %SystemActor{system?: true}

    pages =
      Concept.Pages.Page
      |> Ash.read!(actor: actor, tenant: workspace_id)

    blocks =
      Concept.Pages.Block
      |> Ash.read!(actor: actor, tenant: workspace_id)

    block_page_map = Map.new(blocks, &{&1.id, &1.page_id})
    block_ids = Map.keys(block_page_map)

    links =
      Concept.Knowledge.Link
      |> Ash.read!(actor: actor, tenant: workspace_id)

    {:ok, collection} = Concept.Knowledge.Collections.ensure_for_workspace(workspace_id)

    structural_rels =
      if block_ids == [] do
        []
      else
        Arcana.Graph.Relationship
        |> where([r], r.type in ["CONTAINS", "PARENT_OF"])
        |> where([r], r.source_id in ^block_ids and r.target_id in ^block_ids)
        |> select([r], %{
          source_id: r.source_id,
          target_id: r.target_id,
          type: r.type
        })
        |> Concept.Repo.all()
      end

    communities =
      Arcana.Graph.Community
      |> where([c], c.collection_id == ^collection.id)
      |> select([c], %{
        id: c.id,
        level: c.level,
        summary: c.summary,
        entity_ids: c.entity_ids
      })
      |> Concept.Repo.all()

    edges = build_edges(links, structural_rels, block_page_map)

    page_community_map = build_page_community_map(communities, block_page_map)

    nodes =
      Enum.map(pages, fn page ->
        %{
          id: page.id,
          label: page.title || "Untitled",
          type: "page",
          community_id: Map.get(page_community_map, page.id)
        }
      end)

    communities_out =
      Enum.map(communities, fn comm ->
        node_ids =
          comm.entity_ids
          |> Enum.map(&Map.get(block_page_map, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        %{
          id: comm.id,
          level: comm.level,
          summary: comm.summary || "",
          node_ids: node_ids
        }
      end)

    %{nodes: nodes, edges: edges, communities: communities_out}
  end

  ## Helpers

  defp build_edges(links, structural_rels, block_page_map) do
    authored =
      for link <- links,
          source_page = Map.get(block_page_map, link.source_block_id),
          target_page = Map.get(block_page_map, link.target_block_id),
          source_page != target_page,
          do: %{source: source_page, target: target_page, kind: link.kind}

    structural =
      for rel <- structural_rels,
          source_page = Map.get(block_page_map, rel.source_id),
          target_page = Map.get(block_page_map, rel.target_id),
          source_page != target_page,
          do: %{
            source: source_page,
            target: target_page,
            kind: type_to_kind(rel.type)
          }

    (authored ++ structural)
    |> Enum.uniq()
  end

  defp type_to_kind("CONTAINS"), do: :contains
  defp type_to_kind("PARENT_OF"), do: :parent_of
  defp type_to_kind("USER_" <> rest), do: user_kind(rest)
  defp type_to_kind(type), do: String.downcase(type) |> String.to_atom()

  defp user_kind("RELATES_TO"), do: :relates_to
  defp user_kind("CITES"), do: :cites
  defp user_kind("CONTRADICTS"), do: :contradicts
  defp user_kind("SEE_ALSO"), do: :see_also
  defp user_kind(rest), do: String.downcase(rest) |> String.to_atom()

  defp build_page_community_map(communities, block_page_map) do
    # Map each page to an arbitrary community that contains one of its blocks.
    for comm <- communities,
        entity_id <- comm.entity_ids,
        page_id = Map.get(block_page_map, entity_id),
        not is_nil(page_id),
        reduce: %{} do
      acc ->
        if Map.has_key?(acc, page_id) do
          acc
        else
          Map.put(acc, page_id, comm.id)
        end
    end
  end
end
