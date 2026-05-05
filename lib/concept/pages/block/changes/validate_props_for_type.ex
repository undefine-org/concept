defmodule Concept.Pages.Block.Changes.ValidatePropsForType do
  @moduledoc "Validate the supplied props map against the BlockType module."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      type = Ash.Changeset.get_attribute(cs, :type)
      props = Ash.Changeset.get_attribute(cs, :props) || %{}
      mod = Concept.Pages.BlockTypes.lookup(type)

      case mod.validate_props(props) do
        :ok -> cs
        {:error, msg} -> Ash.Changeset.add_error(cs, field: :props, message: msg)
      end
    end)
  end
end
