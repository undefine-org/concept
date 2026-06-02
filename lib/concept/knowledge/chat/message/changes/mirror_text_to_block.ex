defmodule Concept.Knowledge.Chat.Message.Changes.MirrorTextToBlock do
  @moduledoc """
  After a message is sent, mirror its text into a `Block` under the message
  (PLAN-010 §27): a message's body is the same content unit as a page's body.
  This activates the message-blocks substrate — `Message.blocks` is no longer
  always empty — so:

    * **crystallize** clones real content (the reactor already lists each
      message's blocks), and
    * **ingestion** (container-keyed) makes conversation searchable knowledge.

  The block type comes from the `:block_type` argument (default `:paragraph`);
  the text becomes a lexical document via `Concept.Lexical.from_plain_text/2`.

  Skipped for host turns (the grounded voice streams `text` directly and has no
  composer) and for empty text. Best-effort: a mirror failure must not fail the
  send — the `text` fast-path remains the source of truth for rendering.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    block_type = Ash.Changeset.get_argument(changeset, :block_type) || :paragraph

    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      maybe_mirror(message, block_type)
      {:ok, message}
    end)
  end

  # Only mirror real, member-authored text. Host/agent streamed replies
  # (source != :user) keep the text fast-path and are not block-mirrored here.
  defp maybe_mirror(%{source: :user, text: text} = message, block_type)
       when is_binary(text) do
    if String.trim(text) != "" do
      content = Concept.Lexical.from_plain_text(text, lexical_type(block_type))

      opts = [actor: %{system?: true}, authorize?: false, tenant: message.workspace_id]

      with {:ok, block} <-
             Concept.Pages.create_block(
               :message,
               message.id,
               block_type,
               message.workspace_id,
               nil,
               opts
             ) do
        Concept.Pages.update_content(block, content, opts)
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  defp maybe_mirror(_message, _block_type), do: :ok

  # Map a Concept block type to the lexical node type from_plain_text expects.
  defp lexical_type(:heading_1), do: "heading"
  defp lexical_type(:heading_2), do: "heading"
  defp lexical_type(:heading_3), do: "heading"
  defp lexical_type(:quote), do: "quote"
  defp lexical_type(_), do: "paragraph"
end
