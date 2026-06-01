defmodule Concept.Pages.FractionalIndexPropertyTest do
  @moduledoc """
  Property-based contract for the fractional indexing primitive — the ordering
  carrier shared by every sibling-ordered resource (Page, Block, Record, and
  the Container model). Example tests pin known cases; these pin the
  *universal* invariants StreamData fuzzes across thousands of inputs.

  The module's contract is **valid-or-raise** (see its moduledoc): every
  generator returns a key strictly inside the requested open interval, or
  raises. It never silently returns an out-of-range key. These properties are
  the executable form of that contract — they hold across the FULL alphabet
  (?a..?z), not a hand-picked interior, because the implementation is now
  total-or-loud.

  Invariants:

    * P1 (betweenness)  — ∀ a < b:  a < between(a, b) < b
    * P2 (density)      — between is re-divisible: subdividing toward a bound
                          either yields a strictly-interior key or raises at a
                          true infimum (never returns out of range)
    * P3 (open ends)    — after_(x) > x  and  before_(x) < x  (or raises at floor)
    * P4 (stable sort)  — a run of after_/1 yields strictly increasing positions

  First property test in the codebase; pure (no DB), fast. Establishes the
  StreamData idiom the Container cutover reuses for schema-level invariants.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Concept.Pages.FractionalIndex, as: FI

  # Full-alphabet position generator (?a..?z) — the implementation is total or
  # raises across the entire domain, so the properties draw from all of it,
  # including the floor (?a) and ceil (?z) characters.
  defp position_gen do
    StreamData.string(?a..?z, min_length: 1, max_length: 8)
  end

  # An ordered, strictly-distinct pair {lo, hi} with lo < hi.
  defp ordered_pair_gen do
    StreamData.bind(position_gen(), fn a ->
      StreamData.bind(position_gen(), fn b ->
        cond do
          a < b -> StreamData.constant({a, b})
          b < a -> StreamData.constant({b, a})
          true -> :skip
        end
      end)
    end)
    |> StreamData.filter(&(&1 != :skip))
  end

  describe "P1 — betweenness" do
    property "between(a, b) is strictly interior, or raises (never out of range)" do
      check all({lo, hi} <- ordered_pair_gen()) do
        try do
          mid = FI.between(lo, hi)

          assert lo < mid and mid < hi,
                 "#{inspect(mid)} not strictly within (#{inspect(lo)}, #{inspect(hi)})"
        rescue
          ArgumentError -> :ok
        end
      end
    end
  end

  describe "P2 — density (re-divisible or loud)" do
    property "subdividing toward the lower bound stays interior or raises" do
      check all({lo, hi} <- ordered_pair_gen()) do
        # Repeatedly insert between lo and the previous midpoint. Each step must
        # be strictly interior; at a true infimum the module RAISES (valid-or-
        # raise) — it must never return an out-of-range key. We stop on raise.
        Enum.reduce_while(1..25, hi, fn _i, upper ->
          try do
            mid = FI.between(lo, upper)
            assert lo < mid and mid < upper
            {:cont, mid}
          rescue
            ArgumentError -> {:halt, upper}
          end
        end)
      end
    end
  end

  describe "P3 — open ends" do
    property "after_(x) is strictly greater than x (ascent never exhausts)" do
      check all(x <- position_gen()) do
        assert x < FI.after_(x)
      end
    end

    property "before_(x) is strictly less than x, or raises at the floor" do
      check all(x <- position_gen()) do
        try do
          assert FI.before_(x) < x
        rescue
          ArgumentError -> :ok
        end
      end
    end
  end

  describe "P4 — append-after-last preserves order" do
    property "a run of after_/1 yields strictly increasing, unique positions" do
      check all(n <- StreamData.integer(1..50)) do
        positions = Enum.scan(1..n, FI.initial(), fn _i, prev -> FI.after_(prev) end)

        assert positions == Enum.sort(positions),
               "append-after-last must be monotonically increasing"

        assert length(Enum.uniq(positions)) == length(positions),
               "no two appended positions may collide"
      end
    end
  end

  describe "boundary contract (the discovered defect, now fixed)" do
    test "before_/1 shortens to descend past an all-but-last floor bound" do
      # Descent shortens to the floor prefix (strictly smaller, since a prefix
      # sorts before the longer string). "a" is the maximal such descent here.
      assert FI.before_("aa") == "a"
      assert FI.before_("aaa") == "a"
      assert FI.before_("aaa") < "aaa"
    end

    test "before_/1 at the true floor raises rather than returning out of range" do
      assert_raise ArgumentError, fn -> FI.before_("a") end
    end

    test "between/2 at a true infimum raises rather than fabricating a key" do
      assert_raise ArgumentError, fn -> FI.between("a", "aa") end
    end

    test "ascent past the ceiling lengthens (never raises)" do
      assert FI.after_("z") > "z"
      assert FI.after_("zz") > "zz"
    end
  end
end
