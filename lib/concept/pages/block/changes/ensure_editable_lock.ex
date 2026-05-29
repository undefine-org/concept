defmodule Concept.Pages.Block.Changes.EnsureEditableLock do
  @moduledoc """
  Authorizes a content write against the block's *advisory* edit lock.

  The lock is a human-collaboration concern, not a transactional guarantee:
  it is released on blur and reaped by the `release_expired_locks` cron. A
  content write is permitted whenever the block is **editable by this actor**:

    * the actor is a system actor (`%{system?: true}`) — internal escalation;
    * the block is `:unlocked`;
    * the actor already holds the lock; or
    * the lock is held by someone else but has **expired**
      (`lock_expires_at < now`) — the prior editor is gone.

  Only an *active* lock held by a different actor blocks the write
  (`code: :locked_by_other`).

  ## Why this is self-sufficient (FEAT MCP parity, finding M1)

  Previously this change required the actor to already hold the lock, which a
  human acquires implicitly on focus. An MCP/LLM caller has no "focus" event,
  so `block_update_content` was surfaced but unusable. By gating on
  *editability* rather than *ownership*, a caller may write directly — matching
  the human-level verb "edit this block" — while a live human editor is still
  protected.

  Deliberately does **not** acquire or persist a lock: a one-shot write must
  not leave a dangling lock that would phantom-block humans until the cron
  reaps it. Concurrency stays last-write-wins, exactly as the action already
  was.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, ctx) do
    if editable?(changeset.data, ctx.actor) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        message: "block is locked by another editor",
        code: :locked_by_other
      )
    end
  end

  defp editable?(_block, %{system?: true}), do: true

  defp editable?(%{lock_state: :unlocked}, _actor), do: true

  defp editable?(block, actor) when is_map(actor) do
    self_held? = not is_nil(block.lock_holder_id) and block.lock_holder_id == Map.get(actor, :id)
    self_held? or lock_expired?(block)
  end

  defp editable?(_block, _actor), do: false

  defp lock_expired?(%{lock_expires_at: nil}), do: true

  defp lock_expired?(%{lock_expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end
end
