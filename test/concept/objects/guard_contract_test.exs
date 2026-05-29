defmodule Concept.Objects.GuardContractTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [to_form: 1]
  alias Concept.Objects.Guards

  test "every registered guard implements icon/0 and render_config_form/2" do
    for mod <- Guards.all() do
      assert is_binary(mod.icon()), "#{inspect(mod)} icon/0"
      assert function_exported?(mod, :render_config_form, 2), "#{inspect(mod)} render_config_form/2"
    end
  end

  test "requires_proof config form renders the field key input" do
    html =
      render_component(fn assigns ->
        Concept.Objects.Guards.RequiresProof.render_config_form(%{"field" => "pr_url"}, assigns.form)
      end, form: to_form(%{}))

    assert html =~ "pr_url"
  end

  test "requires_approval config form renders approver options" do
    html =
      render_component(fn assigns ->
        Concept.Objects.Guards.RequiresApproval.render_config_form(%{"by" => "creator"}, assigns.form)
      end, form: to_form(%{}))

    assert html =~ "The creator"
    assert html =~ "Any member"
  end
end
