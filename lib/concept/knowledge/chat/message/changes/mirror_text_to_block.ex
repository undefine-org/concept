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

  ## Scope (T6) & follow-ups

  This activates the substrate (one mirrored block per message, typed via the
  composer's block-type selector). Two clean FUPs build on it:

    * a full in-composer lexical `/`-slash editor (multi-block message bodies),
      replacing the single-type mirror; and
    * crystallize-by-reparent (move blocks) as an alternative to the current
      clone, now that message bodies carry real blocks.
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
      content = mirror_content(text, block_type)

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

  # Build the lexical content for the mirrored block. Headings require a `tag`
  # (h1/h2/h3) on the node — Lexical's HeadingNode.importJSON and
  # Concept.Lexical.to_html/to_markdown all match on it; a bare "heading" type
  # renders/serializes malformed. Other types use the plain paragraph/quote node.
  defp mirror_content(text, bt) when bt in [:heading_1, :heading_2, :heading_3] do
    tag = "h" <> (bt |> Atom.to_string() |> String.replace_prefix("heading_", ""))

    inject_text(Concept.Lexical.empty_heading(heading_level(bt)), text)
    |> ensure_tag(tag)
  end

  defp mirror_content(text, :quote), do: Concept.Lexical.from_plain_text(text, "quote")
  defp mirror_content(text, _), do: Concept.Lexical.from_plain_text(text, "paragraph")

  defp heading_level(:heading_1), do: 1
  defp heading_level(:heading_2), do: 2
  defp heading_level(:heading_3), do: 3

  # Put the message text into the (empty) heading node's first child.
  defp inject_text(%{"root" => %{"children" => [node | rest]} = root} = doc, text) do
    text_node = %{
      "type" => "text",
      "text" => text,
      "format" => 0,
      "detail" => 0,
      "mode" => "normal",
      "style" => "",
      "version" => 1
    }

    %{doc | "root" => %{root | "children" => [Map.put(node, "children", [text_node]) | rest]}}
  end

  defp inject_text(doc, _text), do: doc

  defp ensure_tag(%{"root" => %{"children" => [node | rest]} = root} = doc, tag) do
    %{doc | "root" => %{root | "children" => [Map.put(node, "tag", tag) | rest]}}
  end

  defp ensure_tag(doc, _tag), do: doc
end
