defmodule Concept.Objects.Changes.SlugifyKey do
  @moduledoc """
  Derive a stable `key` from `name` when not explicitly provided.
  The key is the snake_case identifier used in MCP tool names
  (e.g. name "Customer" → key "customer" → tool `create_customer`).
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :key) do
      k when is_binary(k) and k != "" ->
        changeset

      _ ->
        name = Ash.Changeset.get_attribute(changeset, :name) || ""
        Ash.Changeset.force_change_attribute(changeset, :key, slugify(name))
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end
end
