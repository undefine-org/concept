defmodule Concept.Objects.EngineTest do
  @moduledoc """
  Wave 1 engine integration: define an ObjectType + FieldDefs, then create
  Records whose JSONB field-bag is validated against the type's fields.
  """
  use Concept.DataCase, async: true

  alias Concept.Objects

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "obj_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    %{user: user, ws: workspace.id}
  end

  defp new_type(ctx, name \\ "Customer") do
    {:ok, type} =
      Objects.create_object_type(name, actor: ctx.user, tenant: ctx.ws)

    type
  end

  defp add_field(ctx, type, name, field_type, opts \\ %{}) do
    attrs =
      Map.merge(
        %{
          object_type_id: type.id,
          name: name,
          field_type: field_type
        },
        opts
      )

    Concept.Objects.FieldDef
    |> Ash.Changeset.for_create(:create, attrs, actor: ctx.user, tenant: ctx.ws)
    |> Ash.create()
  end

  describe "object type" do
    test "create derives a snake_case key from the name", ctx do
      type = new_type(ctx, "Sales Lead")
      assert type.key == "sales_lead"
      assert type.workspace_id == ctx.ws
    end

    test "key is unique per workspace", ctx do
      _ = new_type(ctx, "Customer")
      assert {:error, _} = Objects.create_object_type("Customer", actor: ctx.user, tenant: ctx.ws)
    end

    test "list returns workspace types", ctx do
      _ = new_type(ctx, "A")
      _ = new_type(ctx, "B")
      {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
      assert length(types) == 2
    end
  end

  describe "field defs" do
    test "fields get ordered fractional positions", ctx do
      type = new_type(ctx)
      {:ok, f1} = add_field(ctx, type, "Name", :text)
      {:ok, f2} = add_field(ctx, type, "ARR", :number)
      assert f1.position < f2.position
      assert f1.key == "name"
    end
  end

  describe "record field validation" do
    setup ctx do
      type = new_type(ctx)
      {:ok, _} = add_field(ctx, type, "Name", :text, %{is_title?: true})
      {:ok, _} = add_field(ctx, type, "ARR", :number)
      {:ok, _} = add_field(ctx, type, "Tier", :select, %{config: %{"options" => ["free", "pro"]}})
      {:ok, _} = add_field(ctx, type, "Owner", :text, %{required?: true})
      %{type: type}
    end

    test "valid fields create a record and derive title", ctx do
      {:ok, rec} =
        Objects.create_record(ctx.type.id, %{"name" => "Acme", "arr" => 1000, "tier" => "pro", "owner" => "me"},
          actor: ctx.user,
          tenant: ctx.ws
        )

      assert rec.fields["arr"] == 1000
      assert rec.title == "Acme"
      assert rec.created_by_id == ctx.user.id
    end

    test "wrong-typed field is rejected", ctx do
      assert {:error, err} =
               Objects.create_record(ctx.type.id, %{"arr" => "lots", "owner" => "me"},
                 actor: ctx.user,
                 tenant: ctx.ws
               )

      assert error_on_fields?(err)
    end

    test "select outside options is rejected", ctx do
      assert {:error, err} =
               Objects.create_record(ctx.type.id, %{"tier" => "enterprise", "owner" => "me"},
                 actor: ctx.user,
                 tenant: ctx.ws
               )

      assert error_on_fields?(err)
    end

    test "missing required field is rejected", ctx do
      assert {:error, err} =
               Objects.create_record(ctx.type.id, %{"name" => "Acme"}, actor: ctx.user, tenant: ctx.ws)

      assert error_on_fields?(err)
    end

    test "unknown field key is rejected", ctx do
      assert {:error, err} =
               Objects.create_record(ctx.type.id, %{"owner" => "me", "bogus" => 1},
                 actor: ctx.user,
                 tenant: ctx.ws
               )

      assert error_on_fields?(err)
    end

    test "update_fields re-validates", ctx do
      {:ok, rec} =
        Objects.create_record(ctx.type.id, %{"name" => "Acme", "owner" => "me"},
          actor: ctx.user,
          tenant: ctx.ws
        )

      assert {:error, _} =
               Objects.update_record_fields(rec, %{"arr" => "nope", "owner" => "me", "name" => "Acme"},
                 actor: ctx.user,
                 tenant: ctx.ws
               )
    end
  end

  describe "record links + assignment" do
    test "link two records and list outgoing", ctx do
      type = new_type(ctx)
      {:ok, _} = add_field(ctx, type, "Name", :text, %{is_title?: true})
      {:ok, a} = Objects.create_record(type.id, %{"name" => "A"}, actor: ctx.user, tenant: ctx.ws)
      {:ok, b} = Objects.create_record(type.id, %{"name" => "B"}, actor: ctx.user, tenant: ctx.ws)

      {:ok, _link} =
        Objects.link_records(a.id, b.id, nil, actor: ctx.user, tenant: ctx.ws)

      {:ok, links} = Objects.list_links_from(a.id, actor: ctx.user, tenant: ctx.ws)
      assert [%{to_record_id: to}] = links
      assert to == b.id
    end

    test "assign a record to the actor and read mine", ctx do
      type = new_type(ctx)
      {:ok, _} = add_field(ctx, type, "Name", :text, %{is_title?: true})
      {:ok, rec} = Objects.create_record(type.id, %{"name" => "A"}, actor: ctx.user, tenant: ctx.ws)
      {:ok, rec} = Objects.assign_record(rec, ctx.user.id, actor: ctx.user, tenant: ctx.ws)
      assert rec.assignee_id == ctx.user.id

      {:ok, mine} = Objects.my_records(actor: ctx.user, tenant: ctx.ws)
      assert Enum.any?(mine, &(&1.id == rec.id))
    end
  end

  defp error_on_fields?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %{field: :fields} -> true
      _ -> false
    end)
  end

  defp error_on_fields?(_), do: false
end
