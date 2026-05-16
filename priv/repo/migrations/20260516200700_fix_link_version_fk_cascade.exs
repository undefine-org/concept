defmodule Concept.Repo.Migrations.FixLinkVersionFkCascade do
  use Ecto.Migration

  def up do
    # knowledge_links table does not exist yet — skip FK creation
  end

  def down do
  end
end
