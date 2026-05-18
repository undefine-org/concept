defmodule Concept.AutoToolsTest do
  use ExUnit.Case, async: false

  alias Concept.AutoToolsFixtures.{FixtureDomain, FixtureDomainWithManualTool, FixtureResource}
  alias Concept.AutoTools.Transformers.SynthesizeTools

  describe "synth_name/2" do
    test "underscores resource module's last segment and joins with action name" do
      assert SynthesizeTools.synth_name(Concept.Pages.Page, :rename) == :page_rename
      assert SynthesizeTools.synth_name(Concept.Pages.Block, :update_props) == :block_update_props

      assert SynthesizeTools.synth_name(Concept.Knowledge.Chat.Conversation, :my_conversations) ==
               :conversation_my_conversations
    end
  end

  describe "AshAi.Info.tools/1 on a fixture domain" do
    test "auto-exposes every described public action" do
      tools = AshAi.Info.tools(FixtureDomain)
      names = tools |> Enum.map(& &1.name) |> MapSet.new()

      assert MapSet.member?(names, :fixture_resource_described_read)
      assert MapSet.member?(names, :fixture_resource_described_generic)
    end

    test "skips actions without a description" do
      tools = AshAi.Info.tools(FixtureDomain)
      names = Enum.map(tools, & &1.name)

      refute :fixture_resource_silent_read in names
      # The `defaults [:read]`-generated `:read` action has no description either.
      refute :fixture_resource_read in names
    end

    test "skips actions listed in the global deny list" do
      tools = AshAi.Info.tools(FixtureDomain)
      names = Enum.map(tools, & &1.name)

      refute :fixture_resource_excluded_read in names
    end

    test "synthesized tool carries the action's description verbatim" do
      tool =
        AshAi.Info.tools(FixtureDomain)
        |> Enum.find(&(&1.name == :fixture_resource_described_read))

      assert tool.description == "Fixture read action with a description."
      assert tool.resource == FixtureResource
      # `tool.action` here is the atom action name on the entity, not the loaded action struct.
      assert tool.action == :described_read
    end
  end

  describe "manual `tool` declaration shadows auto-synthesis" do
    test "manual tool with the same name takes precedence" do
      tool =
        AshAi.Info.tools(FixtureDomainWithManualTool)
        |> Enum.find(&(&1.name == :fixture_resource_described_read))

      assert tool != nil
      assert tool.description == "Manual override — takes precedence over auto-synthesis."
    end

    test "non-colliding described actions are still auto-exposed alongside the manual one" do
      names =
        FixtureDomainWithManualTool
        |> AshAi.Info.tools()
        |> Enum.map(& &1.name)
        |> MapSet.new()

      assert MapSet.member?(names, :fixture_resource_described_read)
      assert MapSet.member?(names, :fixture_resource_described_generic)
    end
  end
end
