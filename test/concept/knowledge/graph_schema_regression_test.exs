defmodule Concept.Knowledge.GraphSchemaRegressionTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Regression test for Arcana.Graph schema stability.

  Locks in the exact field set we depend on from Arcana.Graph.Entity and
  Arcana.Graph.Relationship. CI must fail loudly on Arcana minor bump that
  adds/removes/renames a required field.

  See lib/concept/knowledge/graph_builder.ex for usage.
  """

  # Verified against deps/arcana/lib/arcana/graph/entity.ex
  # Schema fields: id, name, type, description, embedding, metadata,
  # chunk_id (belongs_to :chunk), collection_id (belongs_to :collection),
  # inserted_at, updated_at (from timestamps())
  @entity_fields ~w(
    id
    name
    type
    description
    embedding
    metadata
    chunk_id
    collection_id
    inserted_at
    updated_at
  )a

  # Verified against deps/arcana/lib/arcana/graph/relationship.ex
  # Schema fields: id, type, description, strength, metadata,
  # source_id (belongs_to :source), target_id (belongs_to :target),
  # inserted_at, updated_at (from timestamps())
  @relationship_fields ~w(
    id
    source_id
    target_id
    type
    description
    strength
    metadata
    inserted_at
    updated_at
  )a

  test "Arcana.Graph.Entity schema fields are stable" do
    actual = MapSet.new(Arcana.Graph.Entity.__schema__(:fields))
    expected = MapSet.new(@entity_fields)

    assert actual == expected,
           """
           Arcana.Graph.Entity schema drifted!

           Expected fields: #{inspect(Enum.sort(@entity_fields))}
           Actual fields:   #{inspect(Enum.sort(MapSet.to_list(actual)))}

           Added:   #{inspect(Enum.sort(MapSet.difference(actual, expected)))}
           Removed: #{inspect(Enum.sort(MapSet.difference(expected, actual)))}

           Update Concept.Knowledge.GraphBuilder if needed and adjust this regression test.
           """
  end

  test "Arcana.Graph.Relationship schema fields are stable" do
    actual = MapSet.new(Arcana.Graph.Relationship.__schema__(:fields))
    expected = MapSet.new(@relationship_fields)

    assert actual == expected,
           """
           Arcana.Graph.Relationship schema drifted!

           Expected fields: #{inspect(Enum.sort(@relationship_fields))}
           Actual fields:   #{inspect(Enum.sort(MapSet.to_list(actual)))}

           Added:   #{inspect(Enum.sort(MapSet.difference(actual, expected)))}
           Removed: #{inspect(Enum.sort(MapSet.difference(expected, actual)))}

           Update Concept.Knowledge.GraphBuilder if needed and adjust this regression test.
           """
  end
end
