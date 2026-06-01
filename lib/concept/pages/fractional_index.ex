defmodule Concept.Pages.FractionalIndex do
  @moduledoc """
  LexoRank-style fractional indexing over base-26 lowercase strings.
  Generates positions strictly between two existing strings without
  shifting siblings.

  ## Contract: valid-or-raise

  Every generator returns a key **strictly** within the requested open
  interval, or raises `ArgumentError`. It never returns an out-of-range key.
  This matters because positions sort lexicographically in SQL: a key that
  silently escapes its bounds corrupts sibling order with no error (the bug a
  property test surfaced — see `test/concept/pages/fractional_index_property_test.exs`).

  ## Boundaries

  `?a` is the floor character: no base-26 string is strictly less than `"a"`,
  and none lies strictly between `"a"` and `"aa"`. Such requests raise rather
  than fabricate a key. Descent below an all-floor bound is achieved by
  *shortening* (`before_("aa") == "a"`), never by lengthening (which only ever
  produces a *larger* string). Ascent above a bound lengthens freely, so the
  upper side never exhausts.

  > Unbounded subdivision (insert-at-front more times than the interval has
  > room for) is the one case that raises in normal use. A future upgrade
  > (integer-prefixed LexoRank with rebalancing) removes the ceiling; until
  > then callers at a true infimum get a loud error, not silent corruption.
  """

  @first ?a
  @last ?z

  @doc "Initial position for an empty list."
  def initial, do: <<midpoint(@first, @last + 1)>>

  @doc "Pick a position strictly greater than `left`."
  def after_(nil), do: initial()
  def after_(left) when is_binary(left), do: between(left, nil)

  @doc "Pick a position strictly less than `right`."
  def before_(nil), do: initial()
  def before_(right) when is_binary(right), do: between(nil, right)

  @doc """
  Pick a position strictly between `left` and `right`.
  When both are nil, returns `initial/0`.
  Raises `ArgumentError` if `left >= right`, or if the open interval
  `(left, right)` contains no representable key (a true infimum, e.g.
  `between("a", "aa")`).
  """
  def between(nil, nil), do: initial()

  def between(left, right) when is_binary(left) and (right == nil or left < right) do
    do_between(String.to_charlist(left), if(right, do: String.to_charlist(right), else: []))
    |> List.to_string()
    |> verify!(left, right)
  end

  def between(nil, right) when is_binary(right) do
    do_between([], String.to_charlist(right))
    |> List.to_string()
    |> verify!(nil, right)
  end

  def between(left, right),
    do:
      raise(ArgumentError, "left=#{inspect(left)} not strictly less than right=#{inspect(right)}")

  # core: walk both strings choosing midpoint at the first divergent or available slot
  defp do_between(left, right) do
    walk(left, right, [])
  end

  defp walk([], [], acc), do: acc ++ [midpoint(@first, @last + 1)]

  defp walk([l | lr], [], acc) do
    # right unbounded (ascend): grow above current left character. Lengthening
    # produces a LARGER string, which is the correct direction here.
    if l < @last do
      acc ++ [midpoint(l + 1, @last + 1)]
    else
      walk(lr, [], acc ++ [l])
    end
  end

  defp walk([], [r | rr], acc) do
    # left unbounded (descend): we need a key strictly between `acc` and
    # `acc ++ [r | rr]`. Descent must SHORTEN or step down a non-floor char —
    # never lengthen (which would overshoot above the bound).
    cond do
      r > @first ->
        # Room to step down within this position.
        acc ++ [midpoint(@first, r)]

      rr != [] ->
        # r is the floor char but the bound continues: `acc ++ [@first]` is a
        # strict prefix of the bound (shorter ⇒ lexicographically smaller) and
        # is greater than `acc`. This is the shortening descent.
        acc ++ [r]

      true ->
        # r is the floor char and the bound ends here: the interval
        # (acc, acc ++ [@first]] is empty. No representable key exists below it.
        raise(
          ArgumentError,
          "no key strictly less than #{inspect(List.to_string(acc ++ [r]))} " <>
            "(floor reached; front-insert space exhausted)"
        )
    end
  end

  defp walk([l | lr], [r | rr], acc) do
    cond do
      l == r -> walk(lr, rr, acc ++ [l])
      r - l > 1 -> acc ++ [midpoint(l, r)]
      # adjacent: keep left, then append rest with right=nil and bump left
      true -> walk(lr, [], acc ++ [l])
    end
  end

  defp midpoint(low, high), do: low + div(high - low, 2)

  # Post-condition: the produced key must lie strictly within the requested
  # open interval. Converts any residual algorithmic slip into a loud error
  # rather than silent order corruption (defense in depth behind `walk/3`).
  defp verify!(result, left, right) do
    within? = (is_nil(left) or left < result) and (is_nil(right) or result < right)

    if within? do
      result
    else
      raise(
        ArgumentError,
        "FractionalIndex produced #{inspect(result)} not strictly within " <>
          "(#{inspect(left)}, #{inspect(right)})"
      )
    end
  end
end
