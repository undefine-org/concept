defmodule Concept.Pages.Block.Changes.AssignDefaults do
  @moduledoc "Pull default content/props from the BlockType module if not provided."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      type = Ash.Changeset.get_attribute(cs, :type)
      mod = Concept.Pages.BlockTypes.lookup(type)

      # Ash 3.25 forbids `change_attribute/3` after a changeset is validated
      # (which `for_create/3` does). Defaults are non-validatable seed values,
      # so `force_change_attribute/3` is the correct API here. See ash#1234.
      cs =
        if Ash.Changeset.get_attribute(cs, :content) in [nil, %{}] do
          Ash.Changeset.force_change_attribute(cs, :content, mod.default_content())
        else
          cs
        end

      if Ash.Changeset.get_attribute(cs, :props) in [nil, %{}] do
        Ash.Changeset.force_change_attribute(cs, :props, mod.default_props())
      else
        cs
      end
    end)
  end
end
