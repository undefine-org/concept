defmodule Concept.Credo.Check.LiveViewPurity do
  @moduledoc false
  use Credo.Check,
    id: "EX9001",
    category: :design,
    base_priority: :high,
    explanations: [
      check: """
      LiveView modules and reusable components must not directly construct
      Ash queries / changesets or call Ecto / the Repo. All data access
      flows through domain code-interface functions so that the same call
      path is available to MCP.

      ## Forbidden

      - `Ash.Query` (including `require Ash.Query`)
      - `Ash.Changeset.for_create/for_update/for_destroy/for_action`
      - `Ecto.Query`
      - `Concept.Repo`

      ## Allowed

      - `Concept.<Domain>.<fn>(...)` code-interface calls.
      - `Ash.read`, `Ash.get`, `Ash.create`, `Ash.update`, `Ash.destroy`
        when passed a query/changeset built by a code interface or a
        domain helper. Direct construction is what's forbidden.

      Rationale: see docs/mcp_parity.md \u2014 the LiveView is one projection
      of an Ash action; the MCP tool is another; they must remain
      indistinguishable.
      """
    ]

  @forbidden_aliases [
    {[:Ash, :Query], "Ash.Query"},
    {[:Ecto, :Query], "Ecto.Query"},
    {[:Concept, :Repo], "Concept.Repo"}
  ]

  @forbidden_changeset_for [:for_create, :for_update, :for_destroy, :for_action]

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    if liveview_or_component?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp liveview_or_component?(source_file) do
    path = source_file.filename || ""

    String.contains?(path, "lib/concept_web/live/") or
      String.contains?(path, "lib/concept_web/components/")
  end

  # `require Ash.Query`, `alias Ash.Query`, `import Ash.Query`
  defp traverse({op, _meta, [{:__aliases__, meta, segs} | _]} = ast, issues, issue_meta)
       when op in [:require, :alias, :import] do
    case matching_forbidden(segs) do
      nil -> {ast, issues}
      label -> {ast, [forbidden_alias_issue(label, op, meta, issue_meta) | issues]}
    end
  end

  # `Ash.Query.<call>` / `Ecto.Query.<call>` / `Concept.Repo.<call>`
  defp traverse(
         {{:., meta, [{:__aliases__, _, segs}, _fun]}, _, _} = ast,
         issues,
         issue_meta
       ) do
    case matching_forbidden(segs) do
      nil -> {ast, issues}
      label -> {ast, [forbidden_call_issue(label, meta, issue_meta) | issues]}
    end
  end

  # `Ash.Changeset.for_create(...)` and friends \u2014 only flagged when the
  # function name is one of the for_* variants. `Ash.Changeset` itself is
  # not forbidden (it's referenced internally), only the explicit changeset
  # construction sites are.
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Ash, :Changeset]}, fun]}, _, _} = ast,
         issues,
         issue_meta
       )
       when fun in @forbidden_changeset_for do
    {ast, [forbidden_changeset_issue(fun, meta, issue_meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp matching_forbidden(segs) do
    Enum.find_value(@forbidden_aliases, fn {match, label} ->
      if List.starts_with?(segs, match), do: label
    end)
  end

  defp forbidden_alias_issue(label, op, meta, issue_meta) do
    format_issue(issue_meta,
      message:
        "`#{op} #{label}` is forbidden in LiveViews/components. " <>
          "Move data access into a domain code-interface fn. See AGENTS.md \u2192 MCP Parity.",
      line_no: meta[:line]
    )
  end

  defp forbidden_call_issue(label, meta, issue_meta) do
    format_issue(issue_meta,
      message:
        "`#{label}.*` call is forbidden in LiveViews/components. " <>
          "Move data access into a domain code-interface fn. See AGENTS.md \u2192 MCP Parity.",
      line_no: meta[:line]
    )
  end

  defp forbidden_changeset_issue(fun, meta, issue_meta) do
    format_issue(issue_meta,
      message:
        "`Ash.Changeset.#{fun}/*` is forbidden in LiveViews/components. " <>
          "Use the domain's code-interface fn instead. See AGENTS.md \u2192 MCP Parity.",
      line_no: meta[:line]
    )
  end
end
