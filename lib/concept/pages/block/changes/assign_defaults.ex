defmodule Concept.Pages.Block.Changes.AssignDefaults do
  @moduledoc "Pull default content/props from the BlockType module if not provided."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      type = Ash.Changeset.get_attribute(cs, :type)
      mod = Concept.Pages.BlockTypes.lookup(type)

      cs =
        if Ash.Changeset.get_attribute(cs, :content) in [nil, %{}] do
          Ash.Changeset.change_attribute(cs, :content, mod.default_content())
        else
          cs
        end

      if Ash.Changeset.get_attribute(cs, :props) in [nil, %{}] do
        Ash.Changeset.change_attribute(cs, :props, mod.default_props())
      else
        cs
      end
    end)
  end
end
