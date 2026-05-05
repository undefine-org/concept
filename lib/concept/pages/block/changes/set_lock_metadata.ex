defmodule Concept.Pages.Block.Changes.SetLockMetadata do
  @moduledoc "Records lock holder + acquire/expires timestamps."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    user_id = Ash.Changeset.get_argument(changeset, :user_id)
    ttl = Ash.Changeset.get_argument(changeset, :ttl_seconds) || 30
    now = DateTime.utc_now()
    expires = DateTime.add(now, ttl, :second)

    # for refresh, only the holder may extend
    if (changeset.context[:_validated_holder] || changeset.data.lock_state == :unlocked) or
         changeset.data.lock_holder_id == user_id do
      changeset
      |> Ash.Changeset.force_change_attribute(:lock_holder_id, user_id)
      |> Ash.Changeset.force_change_attribute(
        :lock_acquired_at,
        changeset.data.lock_acquired_at || now
      )
      |> Ash.Changeset.force_change_attribute(:lock_expires_at, expires)
    else
      Ash.Changeset.add_error(changeset, message: "lock_held_by_other", code: :lock_held_by_other)
    end
  end
end
