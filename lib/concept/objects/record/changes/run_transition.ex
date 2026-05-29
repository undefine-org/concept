defmodule Concept.Objects.Record.Changes.RunTransition do
  @moduledoc """
  Move a record to a new workflow state, enforcing the transition's guards.

  Wave 1: sets `state_id` from the `to_state_id` argument. Wave 2 extends this
  to resolve the transition in the workflow graph (rejecting unreachable
  targets) and run each declared guard before committing the state change.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    to_state_id = Ash.Changeset.get_argument(changeset, :to_state_id)
    Ash.Changeset.force_change_attribute(changeset, :state_id, to_state_id)
  end
end
