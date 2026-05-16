defmodule Concept.Pages.Changes.TrimTitle do
  @moduledoc "Trims leading/trailing whitespace from `title` before persistence."
  use Ash.Resource.Change
  require Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :title) do
      nil ->
        changeset

      title when is_binary(title) ->
        Ash.Changeset.change_attribute(changeset, :title, String.trim(title))

      _ ->
        changeset
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, %{title: Ash.Expr.expr(trim(^ref(:title)))}}
  end
end
