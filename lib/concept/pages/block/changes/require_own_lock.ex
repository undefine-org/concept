defmodule Concept.Pages.Block.Changes.RequireOwnLock do
  @moduledoc "Reject content updates unless current actor holds the block lock."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, ctx) do
    actor = ctx.actor

    cond do
      is_map(actor) and Map.get(actor, :system?) == true ->
        changeset

      changeset.data.lock_state == :locked and is_map(actor) and
          changeset.data.lock_holder_id == Map.get(actor, :id) ->
        changeset

      true ->
        Ash.Changeset.add_error(changeset,
          message: "lock not held by actor",
          code: :not_lock_holder
        )
    end
  end
end
