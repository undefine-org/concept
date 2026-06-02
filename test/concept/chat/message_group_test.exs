defmodule Concept.Chat.MessageGroupTest do
  @moduledoc """
  Visual run grouping: consecutive same-sender messages within a time window
  fuse into one run (one avatar/name head). Pure, total, shape-tolerant — the
  structural twin of RailModel.stats/1.
  """
  use ExUnit.Case, async: true

  alias Concept.Chat.MessageGroup

  defp msg(opts) do
    base = ~U[2026-06-01 12:00:00Z]

    %{
      id: Keyword.get(opts, :id, Ash.UUID.generate()),
      source: Keyword.get(opts, :source, :user),
      sender_participant_id: Keyword.get(opts, :sender, "p1"),
      inserted_at: Keyword.get(opts, :at, base)
    }
  end

  test "empty list annotates to empty" do
    assert MessageGroup.annotate([]) == []
  end

  test "first message always starts a run" do
    [a] = MessageGroup.annotate([msg(sender: "p1")])
    assert a.starts_run?
  end

  test "same sender within the window fuses into one run" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      msg(sender: "p1", at: base),
      msg(sender: "p1", at: DateTime.add(base, 30, :second)),
      msg(sender: "p1", at: DateTime.add(base, 60, :second))
    ]

    [a, b, c] = MessageGroup.annotate(msgs)
    assert a.starts_run?
    refute b.starts_run?
    refute c.starts_run?
  end

  test "a different sender starts a new run" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      msg(sender: "p1", at: base),
      msg(sender: "p2", at: DateTime.add(base, 10, :second))
    ]

    [a, b] = MessageGroup.annotate(msgs)
    assert a.starts_run?
    assert b.starts_run?
  end

  test "a large time gap starts a new run even for the same sender" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      msg(sender: "p1", at: base),
      # 10 minutes later (> 300s window)
      msg(sender: "p1", at: DateTime.add(base, 600, :second))
    ]

    [_a, b] = MessageGroup.annotate(msgs)
    assert b.starts_run?
  end

  test "a host turn always starts its own run (no identity to group)" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      msg(source: :host, sender: nil, at: base),
      msg(source: :host, sender: nil, at: DateTime.add(base, 5, :second))
    ]

    [a, b] = MessageGroup.annotate(msgs)
    assert a.starts_run?
    assert b.starts_run?
  end

  test "ends_run? marks the last message of a run" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      msg(sender: "p1", at: base),
      msg(sender: "p1", at: DateTime.add(base, 30, :second)),
      msg(sender: "p2", at: DateTime.add(base, 40, :second))
    ]

    [a, b, c] = MessageGroup.annotate(msgs)
    refute a.ends_run?
    assert b.ends_run?
    assert c.ends_run?
  end

  test "starts_run?/2 (incremental) agrees with annotate for a predecessor" do
    base = ~U[2026-06-01 12:00:00Z]
    prev = msg(sender: "p1", at: base)
    same = msg(sender: "p1", at: DateTime.add(base, 20, :second))
    other = msg(sender: "p2", at: DateTime.add(base, 20, :second))

    refute MessageGroup.starts_run?(prev, same)
    assert MessageGroup.starts_run?(prev, other)
    assert MessageGroup.starts_run?(nil, same)
  end

  test "shape-tolerant: string-keyed maps" do
    base = ~U[2026-06-01 12:00:00Z]

    msgs = [
      %{"source" => "user", "sender_participant_id" => "p1", "inserted_at" => base},
      %{
        "source" => "user",
        "sender_participant_id" => "p1",
        "inserted_at" => DateTime.add(base, 10, :second)
      }
    ]

    [a, b] = MessageGroup.annotate(msgs)
    assert a.starts_run?
    refute b.starts_run?
  end
end
