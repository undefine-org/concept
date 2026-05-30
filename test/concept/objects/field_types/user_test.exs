defmodule Concept.Objects.FieldTypes.UserTest do
  @moduledoc "Unit tests for the :user field type rendering."
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Concept.Objects.FieldTypes.User

  defp render_value(assigns) do
    User.render_value(assigns.value, %{}, assigns)
  end

  describe "render_value/3" do
    test "renders Unassigned when value is nil" do
      html = render_component(&render_value/1, value: nil)
      assert html =~ "Unassigned"
    end

    test "renders Unassigned when member not found" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: Ecto.UUID.generate(), email: "other@example.com"}]
        )

      assert html =~ "Unassigned"
    end

    test "renders human member without agent glyph" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: uid, email: "ada@example.com", role: :member}]
        )

      assert html =~ "ada"
      refute html =~ "🤖"
    end

    test "renders admin member without agent glyph" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: uid, email: "admin@example.com", role: :admin}]
        )

      assert html =~ "admin"
      refute html =~ "🤖"
    end

    test "renders agent member with robot glyph and chip" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: uid, email: "bot@example.com", role: :agent}]
        )

      assert html =~ "bot"
      assert html =~ "🤖"
      assert html =~ "agent"
    end

    test "renders member without role as human (no glyph)" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: uid, email: "plain@example.com"}]
        )

      assert html =~ "plain"
      refute html =~ "🤖"
    end

    test "handles string role key" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{"id" => uid, "email" => "bot@example.com", "role" => "agent"}]
        )

      assert html =~ "🤖"
    end

    test "falls back gracefully when member map has no identifiable role" do
      uid = Ecto.UUID.generate()

      html =
        render_component(&render_value/1,
          value: uid,
          members: [%{id: uid, email: "weird@example.com", role: nil}]
        )

      assert html =~ "weird"
      refute html =~ "🤖"
    end
  end
end
