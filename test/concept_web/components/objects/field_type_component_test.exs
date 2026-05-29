defmodule ConceptWeb.Objects.FieldTypeComponentTest do
  @moduledoc """
  Contract tests for the FieldType render dispatcher and each field type's
  render_value/render_input/render_config_form. Pure component tests — no DB.
  """
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [to_form: 1]

  alias ConceptWeb.Objects.FieldTypeComponent
  alias Concept.Objects.FieldTypes

  defp fd(field_type, config \\ %{}), do: %{field_type: field_type, config: config}

  defp form_field(name, value) do
    to_form(%{name => value})[name]
  end

  describe "every registered field type implements the render contract" do
    test "icon/0, render_value/3, render_input/3 exist for all types" do
      for mod <- FieldTypes.all() do
        assert function_exported?(mod, :icon, 0), "#{inspect(mod)} missing icon/0"
        assert function_exported?(mod, :render_value, 3), "#{inspect(mod)} missing render_value/3"
        assert function_exported?(mod, :render_input, 3), "#{inspect(mod)} missing render_input/3"
        assert is_binary(mod.icon())
      end
    end
  end

  describe "value/1 dispatcher" do
    test "text renders the string" do
      html = render_component(&FieldTypeComponent.value/1, field_def: fd(:text), value: "hello")
      assert html =~ "hello"
    end

    test "text renders an em-dash placeholder when empty" do
      html = render_component(&FieldTypeComponent.value/1, field_def: fd(:text), value: nil)
      assert html =~ "—"
    end

    test "select renders a colored chip for a known option" do
      html =
        render_component(&FieldTypeComponent.value/1,
          field_def: fd(:select, %{"options" => ["low", "high"]}),
          value: "high"
        )

      assert html =~ "high"
      assert html =~ "rounded"
    end

    test "url renders an anchor with target=_blank" do
      html =
        render_component(&FieldTypeComponent.value/1,
          field_def: fd(:url),
          value: "https://example.com/x"
        )

      assert html =~ ~s|href="https://example.com/x"|
      assert html =~ ~s|target="_blank"|
    end

    test "checklist renders a progress count" do
      html =
        render_component(&FieldTypeComponent.value/1,
          field_def: fd(:checklist),
          value: [
            %{"label" => "a", "checked" => true},
            %{"label" => "b", "checked" => false}
          ]
        )

      assert html =~ "1/2"
    end

    test "user resolves a uuid to a member name via :members context" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&FieldTypeComponent.value/1,
          field_def: fd(:user),
          value: uid,
          members: [%{id: uid, email: "ada@example.com"}]
        )

      assert html =~ "ada"
    end

    test "user renders Unassigned when value is nil" do
      html = render_component(&FieldTypeComponent.value/1, field_def: fd(:user), value: nil)
      assert html =~ "Unassigned"
    end

    test "relation renders linked record titles via :options context" do
      rid = Ecto.UUID.generate()

      html =
        render_component(&FieldTypeComponent.value/1,
          field_def: fd(:relation, %{"many" => true}),
          value: [rid],
          options: [%{id: rid, title: "Linked task"}]
        )

      assert html =~ "Linked task"
    end
  end

  describe "input/1 dispatcher" do
    test "text renders a text input bound to the form field" do
      html =
        render_component(&FieldTypeComponent.input/1,
          field_def: fd(:text),
          field: form_field("title", "x")
        )

      assert html =~ ~s|type="text"|
      assert html =~ ~s|value="x"|
    end

    test "select renders an option per configured choice with the current one selected" do
      html =
        render_component(&FieldTypeComponent.input/1,
          field_def: fd(:select, %{"options" => ["low", "high"]}),
          field: form_field("priority", "high")
        )

      assert html =~ "<select"
      assert html =~ ~s|value="low"|
      # the selected option carries both its value and the boolean attr
      assert html =~ ~r/value="high"\s+selected/
    end

    test "user renders a member option list" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&FieldTypeComponent.input/1,
          field_def: fd(:user),
          field: form_field("assignee", uid),
          members: [%{id: uid, email: "ada@example.com"}]
        )

      assert html =~ "<select"
      assert html =~ "ada"
      assert html =~ ~s|selected|
    end
  end

  describe "config_form/1 dispatcher" do
    test "select renders an options textarea" do
      html =
        render_component(&FieldTypeComponent.config_form/1,
          field_def: fd(:select, %{"options" => ["a", "b"]}),
          form: to_form(%{})
        )

      assert html =~ "<textarea"
      assert html =~ "a\nb"
    end

    test "text (no config) renders empty" do
      html =
        render_component(&FieldTypeComponent.config_form/1,
          field_def: fd(:text),
          form: to_form(%{})
        )

      assert String.trim(html) == ""
    end
  end
end
