defmodule Concept.PubsubContractTest do
  @moduledoc """
  Round-trip test for the **PubSub topic ↔ subscriber** boundary.

  ## What this test enforces (and why)

  Every Ash resource that declares a `pub_sub do … end` block specifies:

  * a `module M` (the broadcast bus — by convention `ConceptWeb.Endpoint` in
    this codebase), and
  * a list of publish topic shapes built from a prefix + parts list, where
    string parts are literal and atom parts are substituted from the
    record at broadcast time.

  Both `ConceptWeb.Endpoint.subscribe/1` and
  `Phoenix.PubSub.subscribe(Concept.PubSub, _)` end up on the same
  underlying server (`config :concept_web, pubsub_server: Concept.PubSub`),
  so subscriber-side delivery doesn't break when the bus mismatches. The
  **convention violation** still matters though:

  * `ConceptWeb.Endpoint.subscribe/1` makes the contract explicit (“I'm
    consuming Ash resource broadcasts; expect `%Phoenix.Socket.Broadcast{}`
    envelopes”), which prevents future contributors from pattern-matching
    on a raw map. That bare-map mismatch is the *actual* class of bug we
    hit in `EvaluateAi.wait_for_completion` — the receive loop matched a
    raw map shape while `Ash.Notifier.PubSub` (via Endpoint) wraps in
    `%Phoenix.Socket.Broadcast{}`. The decide_completion unit test pins
    that for one site; this test enforces the convention at every site.

  ## What it does

  1. Scans `lib/` for every `pub_sub do module M; publish ..., parts` triple
     and compiles a regex per publish topic shape (atoms → `[^:]+`).
  2. Scans `lib/` for every PubSub subscribe call site (both APIs).
  3. For each subscriber whose topic-string-prefix matches a resource
     publish shape, asserts the subscribe uses `ConceptWeb.Endpoint`.

  Application-level topics (e.g. `workspace:<ws>:focus_block`, presence)
  that don't match any resource shape are ignored.
  """
  use ExUnit.Case, async: true

  @lib_roots ["lib/concept", "lib/concept_web"]

  test "subscribers to resource-broadcast topic shapes use ConceptWeb.Endpoint.subscribe" do
    publish_shapes = compile_publish_shapes()
    subscribers = scan_subscribers()

    violations =
      for sub <- subscribers,
          sub.shape != nil,
          %{shape: pub_shape, resource: res} <- publish_shapes,
          shapes_match?(sub.shape, pub_shape),
          sub.bus != ConceptWeb.Endpoint do
        Map.merge(sub, %{resource: res, pub_shape: pub_shape})
      end
      |> Enum.uniq_by(&{&1.file, &1.line})

    assert violations == [], format_violations(violations)
  end

  # ---------------------------------------------------------------------------
  # Shape model: a topic is a list of segments where each segment is either
  # a string literal ("workspace", "pages") or `:dyn` (any non-colon run).
  # `["workspace", :dyn, "pages"]` matches `workspace:<anything>:pages`.
  # ---------------------------------------------------------------------------

  defp shapes_match?(a, b) when length(a) != length(b), do: false

  defp shapes_match?(a, b) do
    Enum.zip(a, b)
    |> Enum.all?(fn
      {x, x} -> true
      {:dyn, _} -> true
      {_, :dyn} -> true
      _ -> false
    end)
  end

  # ---------------------------------------------------------------------------
  # pub_sub scanner — extract canonical topic shapes per publish declaration
  # ---------------------------------------------------------------------------

  defp compile_publish_shapes do
    @lib_roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.flat_map(&extract_publishes/1)
  end

  defp extract_publishes(file) do
    ast = file |> File.read!() |> Code.string_to_quoted!(columns: true)
    resource = file |> Path.basename(".ex") |> Macro.camelize()

    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:pub_sub, _meta, [[do: block]]} = node, acc ->
          prefix = extract_field(block, :prefix)

          publishes =
            collect_in_block(block, fn
              {publish_kw, _meta, [_action, parts | _]}
              when publish_kw in [:publish, :publish_all] and is_list(parts) ->
                build_shape(prefix, parts)

              _ ->
                nil
            end)

          {node, Enum.map(publishes, &%{resource: resource, shape: &1}) ++ acc}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp build_shape(prefix, parts) do
    [prefix | Enum.map(parts, &part_to_segment/1)]
  end

  defp part_to_segment(s) when is_binary(s), do: s
  defp part_to_segment(a) when is_atom(a), do: :dyn
  defp part_to_segment(_), do: :dyn

  defp extract_field({:__block__, _, stmts}, key), do: find_in_stmts(stmts, key)
  defp extract_field(stmt, key), do: find_in_stmts([stmt], key)

  defp find_in_stmts(stmts, :prefix) do
    Enum.find_value(stmts, fn
      {:prefix, _, [s]} when is_binary(s) -> s
      _ -> nil
    end)
  end

  defp collect_in_block({:__block__, _, stmts}, fun),
    do: Enum.flat_map(stmts, &collect_one(&1, fun))

  defp collect_in_block(stmt, fun), do: collect_one(stmt, fun)

  defp collect_one(stmt, fun) do
    case fun.(stmt) do
      nil -> []
      result -> [result]
    end
  end

  # ---------------------------------------------------------------------------
  # Subscribe scanner
  # ---------------------------------------------------------------------------

  defp scan_subscribers do
    @lib_roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.flat_map(&extract_subscribes/1)
  end

  defp extract_subscribes(file) do
    ast = file |> File.read!() |> Code.string_to_quoted!(columns: true)

    {_, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Phoenix, :PubSub]}, :subscribe]}, meta,
         [{:__aliases__, _, bus_parts}, topic_ast]} = node,
        acc ->
          {node,
           [
             %{
               file: file,
               line: Keyword.get(meta, :line, 0),
               bus: Module.concat(bus_parts),
               topic_ast: topic_ast,
               shape: topic_ast_to_shape(topic_ast)
             }
             | acc
           ]}

        {{:., _, [{:__aliases__, _, mod_parts}, :subscribe]}, meta, [topic_ast]} = node, acc ->
          mod = Module.concat(mod_parts)

          if mod == ConceptWeb.Endpoint do
            {node,
             [
               %{
                 file: file,
                 line: Keyword.get(meta, :line, 0),
                 bus: ConceptWeb.Endpoint,
                 topic_ast: topic_ast,
                 shape: topic_ast_to_shape(topic_ast)
               }
               | acc
             ]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Convert a topic AST into a canonical shape list (same format as
  # `build_shape/2`). Each colon-separated segment becomes either a literal
  # string or `:dyn` for an interpolation/concatenation/other dynamic input.
  defp topic_ast_to_shape(s) when is_binary(s), do: String.split(s, ":")

  defp topic_ast_to_shape({:<<>>, _, parts}) do
    parts
    |> Enum.flat_map(fn
      s when is_binary(s) ->
        s
        |> String.split(":", trim: false)
        |> Enum.map(fn
          "" -> :sep
          chunk -> {:lit, chunk}
        end)
        |> intersperse_seps()

      _ ->
        [{:lit, :dyn}]
    end)
    |> coalesce_segments()
  end

  defp topic_ast_to_shape({:<>, _, [a, b]}) do
    topic_ast_to_shape(a) ++ topic_ast_to_shape(b)
  end

  defp topic_ast_to_shape(_), do: nil

  # Internal helpers for normalizing the colon-split output of binary segments.
  defp intersperse_seps(list) do
    # `String.split("a:b", ":", trim: false)` already gives `["a", "b"]`. The
    # `""` entries above signal that adjacent colons were present. Here we
    # just emit explicit `:sep` markers between non-empty chunks.
    list
  end

  defp coalesce_segments(tokens) do
    # tokens are `{:lit, "chunk"}`, `{:lit, :dyn}`, or `:sep`. Walk and emit
    # a final list of strings (joined non-dyn neighbours) and `:dyn` atoms.
    tokens
    |> Enum.chunk_by(&match?(:sep, &1))
    |> Enum.reject(&(&1 == [:sep]))
    |> Enum.map(fn chunk ->
      cond do
        Enum.any?(chunk, &(&1 == {:lit, :dyn})) ->
          :dyn

        true ->
          chunk
          |> Enum.map(fn {:lit, s} -> s end)
          |> Enum.join("")
      end
    end)
  end

  defp format_violations(violations) do
    bullets =
      violations
      |> Enum.sort_by(& &1.file)
      |> Enum.map(fn v ->
        "  - #{Path.relative_to_cwd(v.file)}:#{v.line} subscribes via #{inspect(v.bus)}.\n" <>
          "    Topic shape #{inspect(v.shape)} matches the publish shape of " <>
          "#{v.resource}: #{inspect(v.pub_shape)}.\n" <>
          "    Convention: use `ConceptWeb.Endpoint.subscribe/1` for Ash resource topics so the\n" <>
          "    `%Phoenix.Socket.Broadcast{}` envelope contract is explicit at the call site."
      end)
      |> Enum.join("\n\n")

    """
    PubSub convention violation — subscribers to Ash resource broadcast topics
    must use `ConceptWeb.Endpoint.subscribe/1`, not `Phoenix.PubSub.subscribe/2`.

    Both APIs ultimately use the same `Concept.PubSub` server, but the
    `Endpoint.subscribe/1` form makes the `%Phoenix.Socket.Broadcast{}` envelope
    contract explicit and prevents the receive-pattern mismatch class of bug.

    #{bullets}
    """
  end
end
