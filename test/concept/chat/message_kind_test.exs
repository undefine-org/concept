defmodule Concept.Chat.MessageKindTest do
  @moduledoc """
  Contract for the chat render-mode dispatch. Total + shape-tolerant: every
  message maps to exactly one mode, on atom- or string-keyed maps alike.
  """
  use ExUnit.Case, async: true

  alias Concept.Chat.MessageKind

  describe "render_mode/1" do
    test "a person → :human_row" do
      assert MessageKind.render_mode(%{source: :user, sender_participant_id: "p1"}) == :human_row
      # source wins even with a participant id (humans carry one too)
      assert MessageKind.render_mode(%{"source" => "user"}) == :human_row
    end

    test "external agent (participant id, not user) → :agent_row" do
      assert MessageKind.render_mode(%{source: :agent, sender_participant_id: "agent-1"}) ==
               :agent_row
    end

    test "host answering a message (no participant, has response_to) → :host_seep" do
      assert MessageKind.render_mode(%{source: :host, response_to_id: "m1"}) == :host_seep
      assert MessageKind.render_mode(%{"source" => "host", "response_to_id" => "m1"}) ==
               :host_seep
    end

    test "host with no parent → :host_note (fallback, nothing dropped)" do
      assert MessageKind.render_mode(%{source: :host}) == :host_note
      assert MessageKind.render_mode(%{source: :host, response_to_id: nil}) == :host_note
    end

    test "is total — unknown shape still resolves to a host mode" do
      assert MessageKind.render_mode(%{}) == :host_note
    end
  end

  describe "predicates + fusion" do
    test "host?/participant? partition the modes" do
      seep = %{source: :host, response_to_id: "m1"}
      human = %{source: :user}
      agent = %{source: :agent, sender_participant_id: "a1"}

      assert MessageKind.host?(seep)
      refute MessageKind.participant?(seep)
      assert MessageKind.participant?(human)
      assert MessageKind.participant?(agent)
      refute MessageKind.host?(human)
    end

    test "fused_under returns the parent id only for a seep" do
      assert MessageKind.fused_under(%{source: :host, response_to_id: "parent-9"}) == "parent-9"
      assert MessageKind.fused_under(%{source: :user, response_to_id: "x"}) == nil
      assert MessageKind.fused_under(%{source: :host}) == nil
    end
  end
end
