defmodule Concept.Integration.MCPParityTest do
  @moduledoc """
  Enforces the principle of PLAN-007: every public Ash action with a
  `description` is exposed as an MCP tool, and every exposed tool has
  a description for every public argument.

  Tagged `:integration` so it stays out of the fast loop; runs in CI
  via the `precommit` alias and a dedicated CI step.
  """
  use ExUnit.Case, async: false
  @moduletag :integration

  describe "tool surface contract" do
    test "every described public action (less explicit opt-outs) is reachable as an MCP tool" do
      autotools_cfg = Application.get_env(:concept, Concept.AutoTools, [])
      excluded_actions = MapSet.new(Keyword.get(autotools_cfg, :exclude, []))
      excluded_resources = MapSet.new(Keyword.get(autotools_cfg, :exclude_resources, []))

      described_pairs =
        for domain <- Application.get_env(:concept, :ash_domains, []),
            resource <- domain_resources(domain),
            not MapSet.member?(excluded_resources, resource),
            action <- Ash.Resource.Info.actions(resource),
            not is_nil(action.description),
            not MapSet.member?(excluded_actions, {resource, action.name}),
            into: MapSet.new(),
            do: {resource, action.name}

      exposed_pairs =
        all_tools()
        |> Enum.map(fn t -> {t.resource, t.action} end)
        |> MapSet.new()

      missing = MapSet.difference(described_pairs, exposed_pairs)

      assert MapSet.size(missing) == 0,
             "Actions described but not exposed as MCP tools:\n  " <>
               (missing
                |> MapSet.to_list()
                |> Enum.map_join("\n  ", &inspect/1))
    end

    test "every exposed tool has a description" do
      for tool <- all_tools() do
        action = Ash.Resource.Info.action(tool.resource, tool.action)
        description = tool.description || (action && action.description)

        refute is_nil(description),
               "Tool :#{tool.name} (#{inspect(tool.resource)}.#{tool.action}) is exposed without a description."
      end
    end

    test "every public argument on an exposed action has a description" do
      missing =
        for tool <- all_tools(),
            action = Ash.Resource.Info.action(tool.resource, tool.action),
            action != nil,
            arg <- action.arguments,
            arg.public?,
            is_nil(arg.description) do
          "#{tool.name}.#{arg.name}"
        end

      assert missing == [],
             "Tool arguments missing descriptions:\n  " <> Enum.join(missing, "\n  ")
    end
  end

  describe "docs/mcp_surface.md is committed" do
    test "the file exists" do
      assert File.exists?("docs/mcp_surface.md"),
             "Run `mix concept.docs.mcp_surface` to generate it."
    end

    test "is in sync with the live surface (no drift)" do
      # Don't run the task itself (it'd boot the app); just compare file
      # contents against what render_markdown would produce.
      committed = File.read!("docs/mcp_surface.md")

      generated =
        apply(Mix.Tasks.Concept.Docs.McpSurface, :render_markdown, [])

      assert committed == generated,
             "docs/mcp_surface.md drift detected. Run `mix concept.docs.mcp_surface`."
    end
  end

  # ─── helpers ───────────────────────────────────────────────────────────────

  defp domain_resources(domain) do
    domain
    |> Spark.Dsl.Extension.get_entities([:resources])
    |> Enum.map(& &1.resource)
  end

  defp all_tools do
    for domain <- Application.get_env(:concept, :ash_domains, []),
        tool <- AshAi.Info.tools(domain) do
      tool
    end
  end
end
