defmodule ConceptWeb.Components.BlockRenderListsTest do
  @moduledoc """
  C-1 (G22): list/to-do blocks must render as real lists/checkboxes, and the
  marker treatment must come from the *type module's* editor_class/0 — never a
  hardcoded type list in the dispatcher. These assert the projected class plus
  the prop-driven checkbox marker.
  """
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Concept.Pages.BlockTypes

  defp block(type, props \\ %{}) do
    %{
      id: Ecto.UUID.generate(),
      type: type,
      content: Concept.Lexical.empty_paragraph(),
      props: props,
      children: %Ash.NotLoaded{}
    }
  end

  defp render_block(block) do
    render_component(&ConceptWeb.BlockRender.block/1, %{block: block})
  end

  test "type modules declare distinct list editor classes (single source of truth)" do
    assert BlockTypes.lookup(:bulleted_list_item).editor_class() =~ "ora-list--bulleted"
    assert BlockTypes.lookup(:numbered_list_item).editor_class() =~ "ora-list--numbered"
    assert BlockTypes.lookup(:to_do).editor_class() =~ "ora-list--todo"
  end

  test "bulleted list block renders with the bulleted marker class" do
    html = render_block(block(:bulleted_list_item))
    assert html =~ "ora-list--bulleted"
  end

  test "numbered list block renders with the numbered marker class" do
    html = render_block(block(:numbered_list_item))
    assert html =~ "ora-list--numbered"
  end

  test "unchecked to-do renders a clickable, unpressed checkbox" do
    html = render_block(block(:to_do, %{"checked" => false}))
    assert html =~ "ora-list--todo"
    assert html =~ "ora-todo-check"
    assert html =~ ~s(phx-click="toggle_check")
    assert html =~ ~s(aria-pressed="false")
    assert html =~ ~s(data-checked="false")
  end

  test "checked to-do reflects pressed state and the check glyph" do
    html = render_block(block(:to_do, %{"checked" => true}))
    assert html =~ ~s(aria-pressed="true")
    assert html =~ ~s(data-checked="true")
    # the hero-check glyph only renders when checked
    assert html =~ "hero-check"
  end

  test "non-todo text blocks carry no checkbox (marker is prop-driven, not type-driven)" do
    html = render_block(block(:bulleted_list_item))
    refute html =~ "ora-todo-check"

    html2 = render_block(block(:paragraph))
    refute html2 =~ "ora-todo-check"
  end
end
