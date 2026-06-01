defmodule Concept.Chat.MessageKind do
  @moduledoc """
  The single source of truth for **how a chat message renders** — the content-
  layer twin of `Concept.Pages.BlockType`'s `render_kind/0`. The chat template
  dispatches on `render_mode/1` rather than branching on `source` /
  `sender_participant_id` / `response_to_id` inline at a dozen sites.

  ## The model (PLAN-010 §6 / chat deep-dive)

  A conversation is anchored to a **host** (a page or the workspace). The host
  is **not a participant** — it has a *grounded voice* that **seeps** into the
  thread. So a message renders one of four ways:

    * `:human_row`  — a person spoke (`source: :user`). Slack-like: avatar +
      name + timestamp, left-aligned. The inter-team-comms substrate.
    * `:host_seep`  — the host's grounded voice answered a specific message
      (`source: :host`, has `response_to_id`). Renders as a **continuation
      fused to the message it answers** — no avatar, no timeline row. A voice,
      not a person.
    * `:host_note`  — the host spoke without answering a specific message
      (`source: :host`, no `response_to_id`). Rare; rendered as a standalone
      grounded note (fallback so nothing is dropped).
    * `:agent_row`  — an external agent member spoke (`source: :agent`, has a
      `sender_participant_id`). A real participant → its own row.

  Field access is shape-tolerant (atom- or string-keyed maps, structs) so the
  same predicate works on Ash structs and on streamed/serialized message maps.
  """

  @type mode :: :human_row | :host_seep | :host_note | :agent_row

  @doc """
  The render mode for a message. Total: every message maps to exactly one mode.
  """
  @spec render_mode(map()) :: mode()
  def render_mode(message) do
    cond do
      source(message) in [:user, "user"] -> :human_row
      not is_nil(participant_id(message)) -> :agent_row
      not is_nil(response_to_id(message)) -> :host_seep
      true -> :host_note
    end
  end

  @doc "True when the message is the host's grounded voice (seep or note)."
  @spec host?(map()) :: boolean()
  def host?(message), do: render_mode(message) in [:host_seep, :host_note]

  @doc "True when a real identity spoke (human or external agent)."
  @spec participant?(map()) :: boolean()
  def participant?(message), do: render_mode(message) in [:human_row, :agent_row]

  @doc """
  The id of the message this one is fused under, or nil. Only meaningful for
  `:host_seep`; lets the template bind a seep beneath its parent message.
  """
  @spec fused_under(map()) :: binary() | nil
  def fused_under(message) do
    case render_mode(message) do
      :host_seep -> response_to_id(message)
      _ -> nil
    end
  end

  # ── shape-tolerant field access ──────────────────────────────────────────

  defp source(%{source: s}), do: s
  defp source(%{"source" => s}), do: s
  defp source(_), do: nil

  defp participant_id(%{sender_participant_id: id}), do: id
  defp participant_id(%{"sender_participant_id" => id}), do: id
  defp participant_id(_), do: nil

  defp response_to_id(%{response_to_id: id}), do: id
  defp response_to_id(%{"response_to_id" => id}), do: id
  defp response_to_id(_), do: nil
end
