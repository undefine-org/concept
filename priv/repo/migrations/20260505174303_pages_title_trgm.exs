defmodule Concept.Repo.Migrations.PagesTitleTrgm do
  @moduledoc "Adds pg_trgm GIN index on pages.title for fast ILIKE search."

  use Ecto.Migration

  def up do
    execute(
      "CREATE INDEX IF NOT EXISTS pages_title_trgm_idx ON pages USING gin (title gin_trgm_ops)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS pages_title_trgm_idx")
  end
end
