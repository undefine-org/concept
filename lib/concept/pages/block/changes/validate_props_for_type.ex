defmodule Concept.Pages.Block.Changes.ValidatePropsForType do
  @moduledoc "Validate the supplied props map against the BlockType module."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      type = Ash.Changeset.get_attribute(cs, :type)
      props = Ash.Changeset.get_attribute(cs, :props) || %{}
      mod = Concept.Pages.BlockTypes.lookup(type)

      Concept.Resources.Changes.TypedJsonb.put_result(cs, :props, mod.validate_props(props))
    end)
  end
end
