defmodule Concept.Chat.MessageGroup do
  @moduledoc """
  Visual grouping of consecutive messages — the structural twin of
  `Concept.Chat.MessageKind` and `Concept.Chat.RailModel`: a pure, total,
  dependency-free projection that derives a trait once, so the template never
  re-derives it (or peeks at a sibling) per render.

  A *run* is a maximal sequence of adjacent messages that share a sender and
  render mode within a short time window. The first message of a run carries
  `starts_run?` (render the avatar + name); the rest suppress them and tuck up
  under the head — the Slack/Linear "one header per burst" reading.

  ## Why a function, not template logic

  LiveView streams render each item independently and cannot see a neighbour at
  render time. So adjacency is computed *when data enters the stream* and
  carried as a field on the row. Critically, `starts_run?` depends only on a
  message's **predecessor** — which never changes when a newer message is
  appended — so the trait is stable under incremental `stream_insert(at: -1)`:
  a row's grouping never needs retroactive correction. (`ends_run?` looks
  forward and is advisory spacing only; a re-stream recomputes it from the
  current list.)

  Shape-tolerant (atom- or string-keyed maps, or Ash structs) like its sibling
  projections.
  """

  # Messages within this window from the same sender fuse into one run; a gap
  # larger than this starts a fresh run even for the same sender (a burst is
  # bounded in time, the way a chat reads).
  @run_window_seconds 300

  @typedoc "A message annotated with its run position."
  @type annotated :: %{message: map(), starts_run?: boolean(), ends_run?: boolean()}

  @doc """
  Annotate an **oldest-first** list of messages with run boundaries.

  Returns each message wrapped as `%{message:, starts_run?:, ends_run?:}`.
  Order is preserved. An empty list returns `[]`.
  """
  @spec annotate([map()]) :: [annotated()]
  def annotate([]), do: []

  def annotate(messages) when is_list(messages) do
    count = length(messages)

    messages
    |> Enum.with_index()
    |> Enum.map(fn {message, i} ->
      prev = if i > 0, do: Enum.at(messages, i - 1)
      next = if i < count - 1, do: Enum.at(messages, i + 1)

      %{
        message: message,
        starts_run?: boundary?(prev, message),
        ends_run?: boundary?(message, next)
      }
    end)
  end

  @doc """
  The run-start trait for a single message given its predecessor — the only
  input incremental inserts need. `nil` predecessor (first message) always
  starts a run.
  """
  @spec starts_run?(map() | nil, map()) :: boolean()
  def starts_run?(prev, message), do: boundary?(prev, message)

  # A boundary exists between `a` and `b` when `b` begins a new run relative to
  # `a`: different sender, different render mode, a host turn (always its own
  # head), or too large a time gap. `nil` on either side is a boundary.
  defp boundary?(nil, _b), do: true
  defp boundary?(_a, nil), do: true

  defp boundary?(a, b) do
    different_sender?(a, b) or different_mode?(a, b) or host_turn?(b) or time_gap?(a, b)
  end

  defp different_sender?(a, b), do: sender_id(a) != sender_id(b)

  defp different_mode?(a, b),
    do: Concept.Chat.MessageKind.render_mode(a) != Concept.Chat.MessageKind.render_mode(b)

  # The host's grounded voice has no identity; each host turn stands alone.
  defp host_turn?(b), do: Concept.Chat.MessageKind.host?(b)

  defp time_gap?(a, b) do
    with %DateTime{} = ta <- inserted_at(a),
         %DateTime{} = tb <- inserted_at(b) do
      abs(DateTime.diff(tb, ta, :second)) > @run_window_seconds
    else
      _ -> false
    end
  end

  defp sender_id(%{sender_participant_id: id}), do: id
  defp sender_id(%{"sender_participant_id" => id}), do: id
  defp sender_id(_), do: nil

  defp inserted_at(%{inserted_at: t}), do: t
  defp inserted_at(%{"inserted_at" => t}), do: t
  defp inserted_at(_), do: nil
end
