defmodule Concept.Repo.Migrations.AddPrimaryToWorkspaces do
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      add :primary?, :boolean, null: false, default: false
    end
  end
end
