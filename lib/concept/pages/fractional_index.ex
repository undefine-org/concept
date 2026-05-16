defmodule Concept.Pages.FractionalIndex do
  @moduledoc """
  LexoRank-style fractional indexing over base-26 lowercase strings.
  Generates positions strictly between two existing strings without
  shifting siblings.
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
  Raises if `left >= right`.
  """
  def between(nil, nil), do: initial()

  def between(left, right) when is_binary(left) and (right == nil or left < right) do
    do_between(String.to_charlist(left), if(right, do: String.to_charlist(right), else: []))
    |> List.to_string()
  end

  def between(nil, right) when is_binary(right) do
    do_between([], String.to_charlist(right)) |> List.to_string()
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
    # right unbounded: grow above current left character
    if l < @last do
      acc ++ [midpoint(l + 1, @last + 1)]
    else
      walk(lr, [], acc ++ [l])
    end
  end

  defp walk([], [r | rr], acc) do
    # left unbounded: shrink below current right character
    if r > @first do
      acc ++ [midpoint(@first, r)]
    else
      walk([], rr, acc ++ [r])
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
end
