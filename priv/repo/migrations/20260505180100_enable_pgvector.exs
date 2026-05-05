defmodule Concept.Repo.Migrations.EnablePgvector do
  @moduledoc """
  Enable the pgvector extension required by Arcana for vector embeddings.
  This MUST run before Arcana's own migrations.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS vector", "CREATE EXTENSION IF NOT EXISTS vector")
  end
end
