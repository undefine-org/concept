defmodule ConceptWeb.ObjectTypeEditorTest do
  @moduledoc "E1: object type list/create/rename + field add/edit/reorder."
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ote_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user, ws: ws}
  end

  describe "index" do
    test "lists seeded Task type and creates a new type", %{conn: conn, ws: ws, user: user} do
      {:ok, view, html} = live(conn, ~p"/w/#{ws.slug}/types")
      assert html =~ "Object types"
      assert html =~ "Task"

      html =
        view
        |> form("#new-type-form", %{"name" => "Customer"})
        |> render_submit()

      assert html =~ "Customer"

      {:ok, types} = Objects.list_object_types(actor: user, tenant: ws.id)
      assert Enum.any?(types, &(&1.name == "Customer"))
    end

    test "the seeded Task type is badged system", %{conn: conn, ws: ws} do
      {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/types")
      assert html =~ "system"
    end
  end

  describe "edit" do
    setup %{user: user, ws: ws} do
      {:ok, type} = Objects.create_object_type("Customer", actor: user, tenant: ws.id)
      %{type: type}
    end

    test "renames a type", %{conn: conn, ws: ws, user: user, type: type} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      view
      |> form("#rename-type-form", %{"type_id" => type.id, "name" => "Client"})
      |> render_submit()

      {:ok, reloaded} = Objects.get_object_type(type.id, actor: user, tenant: ws.id)
      assert reloaded.name == "Client"
    end

    test "adds a field via the type picker", %{conn: conn, ws: ws, user: user, type: type} do
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      view
      |> form("#add-field-form", %{"name" => "Company", "field_type" => "text"})
      |> render_submit()

      {:ok, fields} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)
      assert Enum.any?(fields, &(&1.name == "Company" and &1.field_type == :text))
    end

    test "adds a select field and saves its options via the config form", %{
      conn: conn,
      ws: ws,
      user: user,
      type: type
    } do
      {:ok, _} = Objects.create_field_def(type.id, "Tier", :select, actor: user, tenant: ws.id)
      {:ok, [fd]} = filter_fields(type, user, ws, "Tier")

      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      view
      |> element("#field-#{fd.id} form")
      |> render_change(%{"field_id" => fd.id, "name" => "Tier", "options" => "free\npro\nenterprise"})

      {:ok, [updated]} = filter_fields(type, user, ws, "Tier")
      assert updated.config["options"] == ["free", "pro", "enterprise"]
    end

    test "unchecking required persists false (hidden fallback)", %{
      conn: conn,
      ws: ws,
      user: user,
      type: type
    } do
      {:ok, fd} =
        Objects.create_field_def(type.id, "Owner", :text,
          actor: user,
          tenant: ws.id
        )

      {:ok, fd} = Objects.update_field_def(fd, "Owner", true, %{}, actor: user, tenant: ws.id)
      assert fd.required? == true

      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      view
      |> element("#field-#{fd.id} form")
      |> render_change(%{"field_id" => fd.id, "name" => "Owner", "required" => "false"})

      {:ok, [updated]} = filter_fields(type, user, ws, "Owner")
      assert updated.required? == false
    end

    test "reorders fields with the up/down controls", %{
      conn: conn,
      ws: ws,
      user: user,
      type: type
    } do
      {:ok, a} = Objects.create_field_def(type.id, "Alpha", :text, actor: user, tenant: ws.id)
      {:ok, b} = Objects.create_field_def(type.id, "Beta", :text, actor: user, tenant: ws.id)

      {:ok, before} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)
      a_idx = Enum.find_index(before, &(&1.id == a.id))
      b_idx = Enum.find_index(before, &(&1.id == b.id))
      assert a_idx < b_idx

      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      view
      |> element("#field-#{b.id} button[phx-value-dir='up']")
      |> render_click()

      {:ok, after_fields} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)
      a_idx2 = Enum.find_index(after_fields, &(&1.id == a.id))
      b_idx2 = Enum.find_index(after_fields, &(&1.id == b.id))
      assert b_idx2 < a_idx2

      # positions must stay distinct (single-write reorder, no swap collision)
      positions = Enum.map(after_fields, & &1.position)
      assert positions == Enum.uniq(positions)
    end

    test "moving the last field down is a no-op (boundary)", %{
      conn: conn,
      ws: ws,
      user: user,
      type: type
    } do
      {:ok, a} = Objects.create_field_def(type.id, "Aaa", :text, actor: user, tenant: ws.id)
      {:ok, view, _} = live(conn, ~p"/w/#{ws.slug}/types/#{type.id}")

      {:ok, before} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)

      view
      |> element("#field-#{a.id} button[phx-value-dir='down']")
      |> render_click()

      {:ok, after_fields} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)
      assert Enum.map(before, & &1.id) == Enum.map(after_fields, & &1.id)
    end
  end

  defp filter_fields(type, user, ws, name) do
    {:ok, fields} = Objects.list_field_defs(type.id, actor: user, tenant: ws.id)
    {:ok, Enum.filter(fields, &(&1.name == name))}
  end
end
