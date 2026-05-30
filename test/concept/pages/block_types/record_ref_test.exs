defmodule Concept.Pages.BlockTypes.RecordRefTest do
  @moduledoc """
  Wave 5: the record_ref block renders a referenced record's live state, and
  is wired into the registry (slash menu, props validation). The seam between
  the document layer and the entity layer.
  """
  use Concept.DataCase, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Concept.Pages.BlockTypes.RecordRef
  alias Concept.{Objects, Pages}

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rref_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Doc", ws.id, nil, actor: user, tenant: ws.id)
    %{user: user, ws: ws.id, page: page}
  end

  describe "registry contract" do
    test "is registered with a known render kind and props validation" do
      assert RecordRef in Concept.Pages.BlockTypes.all()
      assert RecordRef.render_kind() == :static
      assert RecordRef.validate_props(%{"record_id" => nil}) == :ok
      assert RecordRef.validate_props(%{"record_id" => Ecto.UUID.generate()}) == :ok
      assert {:error, _} = RecordRef.validate_props(%{"record_id" => 123})
    end

    test "appears in the slash menu feed" do
      items = Concept.Pages.BlockTypes.slash_menu_items()
      assert Enum.any?(items, &(&1.type == :record_ref))
    end

    test "a record_ref block can be created on a page", ctx do
      {:ok, block} =
        Pages.create_block(ctx.page.id, :record_ref, ctx.ws, nil, actor: ctx.user, tenant: ctx.ws)

      assert block.type == :record_ref
    end
  end

  describe "render" do
    setup ctx do
      {:ok, types} = Objects.list_object_types(actor: ctx.user, tenant: ctx.ws)
      task = Enum.find(types, &(&1.key == "task"))

      {:ok, record} =
        Objects.create_record(task.id, %{fields: %{"title" => "Ship the thing"}},
          actor: ctx.user,
          tenant: ctx.ws
        )

      %{task: task, record: record}
    end

    test "renders the referenced record's title", ctx do
      block = %Concept.Pages.Block{
        workspace_id: ctx.ws,
        props: %{"record_id" => ctx.record.id}
      }

      html = render_block(block)
      assert html =~ "Ship the thing"
    end

    test "renders the live workflow state label once the record is moved", ctx do
      {:ok, states} =
        Objects.list_workflow_states(ctx.task.workflow_id, actor: ctx.user, tenant: ctx.ws)

      todo = Enum.find(states, &(&1.category == :todo))

      # records auto-start in Backlog; move to Todo via the seeded edge
      {:ok, _} =
        Objects.transition_record(ctx.record, todo.id, actor: ctx.user, tenant: ctx.ws)

      block = %Concept.Pages.Block{
        workspace_id: ctx.ws,
        props: %{"record_id" => ctx.record.id}
      }

      html = render_block(block)
      assert html =~ "Todo"
    end

    test "renders a link affordance when record_id is nil", ctx do
      block = %Concept.Pages.Block{id: Ecto.UUID.generate(), workspace_id: ctx.ws, props: %{"record_id" => nil}}
      html = render_block(block)
      assert html =~ "Link a record"
      assert html =~ "open_record_picker"
    end

    test "renders a link affordance for a missing record", ctx do
      block = %Concept.Pages.Block{
        id: Ecto.UUID.generate(),
        workspace_id: ctx.ws,
        props: %{"record_id" => Ecto.UUID.generate()}
      }

      html = render_block(block)
      assert html =~ "Link a record"
      assert html =~ "open_record_picker"
    end
  end

  defp render_block(block) do
    assigns = Map.put(%{__changed__: nil}, :block, block)

    assigns
    |> RecordRef.render()
    |> rendered_to_string()
  end
end
