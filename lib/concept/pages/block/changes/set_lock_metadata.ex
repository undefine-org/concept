defmodule Concept.Pages.Block.Changes.SetLockMetadata do
  @moduledoc "Records lock holder + acquire/expires timestamps."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, ctx) do
    user_id = Ash.Changeset.get_argument(changeset, :user_id)

    case validate_actor(user_id, ctx.actor) do
      :ok ->
        apply_lock_metadata(changeset, user_id)

      {:error, message} ->
        Ash.Changeset.add_error(changeset, message: message, code: :actor_mismatch)
    end
  end

  # The `user_id` argument names the lock holder; it must be the acting user.
  # A system actor (internal escalation) may set any holder.
  defp validate_actor(_user_id, %{system?: true}), do: :ok
  defp validate_actor(user_id, %{id: actor_id}) when user_id == actor_id, do: :ok
  defp validate_actor(_user_id, _actor), do: {:error, "user_id must match the acting user"}

  defp apply_lock_metadata(changeset, user_id) do
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
