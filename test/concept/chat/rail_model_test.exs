defmodule Concept.Chat.RailModelTest do
  @moduledoc """
  The adaptive rail projection: a flat conversation list → host-grouped rail
  tree. Pure, total, dependency-free (no DB). The structural twin of
  `Concept.Chat.MessageKind` — dispatch on a derived trait (`mode`), never on
  `length(conversations)` scattered in a template.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Concept.Chat.RailModel

  # A minimal conversation shape — RailModel is shape-tolerant (structs or maps).
  defp conv(host_type, host_id, opts \\ []) do
    %{
      id: Keyword.get(opts, :id, Ash.UUID.generate()),
      host_type: host_type,
      host_id: host_id,
      title: Keyword.get(opts, :title),
      updated_at: Keyword.get(opts, :updated_at, DateTime.utc_now())
    }
  end

  describe "group_by_host/1 — the adaptive rule" do
    test "a host with >= 2 conversations becomes a :category" do
      p = Ash.UUID.generate()
      groups = RailModel.group_by_host([conv(:page, p), conv(:page, p)])

      assert [%{host_type: :page, host_id: ^p, mode: :category, conversations: convs}] = groups
      assert length(convs) == 2
    end

    test "a host with exactly 1 conversation is :inline" do
      p = Ash.UUID.generate()
      assert [%{host_type: :page, host_id: ^p, mode: :inline}] =
               RailModel.group_by_host([conv(:page, p)])
    end

    test "a host with 0 conversations does not appear" do
      # Vacuously: nothing in → nothing out.
      assert [] = RailModel.group_by_host([])
    end

    test "the :workspace host (host_id nil) groups as one host" do
      groups = RailModel.group_by_host([conv(:workspace, nil), conv(:workspace, nil)])
      assert [%{host_type: :workspace, host_id: nil, mode: :category, conversations: c}] = groups
      assert length(c) == 2
    end

    test "distinct host_ids of the same type are distinct hosts" do
      a = Ash.UUID.generate()
      b = Ash.UUID.generate()
      groups = RailModel.group_by_host([conv(:page, a), conv(:page, b)])
      # Two separate pages, each with one conversation → two inline hosts.
      assert length(groups) == 2
      assert Enum.all?(groups, &(&1.mode == :inline))
    end
  end

  describe "section ordering" do
    test "hosts are ordered by Hostable.types() position" do
      # types() = [:workspace, :page] today; workspace must precede page.
      page = Ash.UUID.generate()
      groups = RailModel.group_by_host([conv(:page, page), conv(:workspace, nil)])
      assert [%{host_type: :workspace}, %{host_type: :page}] = groups
    end

    test "section_for/1 maps a host_type to a display section" do
      assert RailModel.section_for(:workspace) == :workspace
      assert RailModel.section_for(:page) == :pages
      assert RailModel.section_for(:user) == :direct_messages
    end
  end

  describe "host-native glyph (not '#')" do
    test "glyph/1 is a hero icon per host kind, never a hashtag" do
      assert RailModel.glyph(:page) =~ "hero-"
      assert RailModel.glyph(:workspace) =~ "hero-"
      assert RailModel.glyph(:user) =~ "hero-"
      refute RailModel.glyph(:page) =~ "#"
    end
  end

  describe "totality (property)" do
    # An atom drawn from the registry's valid host types.
    defp host_type_gen, do: StreamData.member_of(Concept.Hostable.types())

    property "every conversation lands in exactly one host group; counts are conserved" do
      check all(
              specs <-
                StreamData.list_of(
                  StreamData.tuple({host_type_gen(), StreamData.member_of([:a, :b, :c])}),
                  max_length: 30
                )
            ) do
        convs =
          Enum.map(specs, fn {ht, slot} ->
            # :workspace always has nil host_id; others map the slot to a stable uuid.
            host_id = if ht == :workspace, do: nil, else: slot_uuid(slot)
            conv(ht, host_id)
          end)

        groups = RailModel.group_by_host(convs)

        # Conservation: no conversation lost or duplicated.
        regrouped = groups |> Enum.flat_map(& &1.conversations) |> length()
        assert regrouped == length(convs)

        # Mode invariant: matches the cardinality rule for every group.
        assert Enum.all?(groups, fn g ->
                 (length(g.conversations) >= 2 and g.mode == :category) or
                   (length(g.conversations) == 1 and g.mode == :inline)
               end)

        # Ordering invariant: sections appear in Hostable.types() order.
        order = Concept.Hostable.types()
        positions = Enum.map(groups, fn g -> Enum.find_index(order, &(&1 == g.host_type)) end)
        assert positions == Enum.sort(positions)
      end
    end

    defp slot_uuid(:a), do: "00000000-0000-0000-0000-0000000000a1"
    defp slot_uuid(:b), do: "00000000-0000-0000-0000-0000000000b2"
    defp slot_uuid(:c), do: "00000000-0000-0000-0000-0000000000c3"
  end
end
