defmodule ConceptWeb.Objects.RecordDetailTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Concept.Objects

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rd_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, types} = Objects.list_object_types(actor: user, tenant: ws.id)
    task = Enum.find(types, &(&1.key == "task"))

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user, ws: ws, task: task}
  end

  test "clicking a card opens the slide-over with the record title", ctx do
    {:ok, rec} =
      Objects.create_record(ctx.task.id, %{fields: %{"title" => "Open me"}},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/tasks")

    view |> element("#task-#{rec.id}") |> render_click()

    assert has_element?(view, "#record-detail-#{rec.id}")
    assert render(view) =~ "Move to"
  end

  test "editing a field autosaves and re-syncs the title", ctx do
    {:ok, rec} =
      Objects.create_record(ctx.task.id, %{fields: %{"title" => "Before"}},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/tasks")
    view |> element("#task-#{rec.id}") |> render_click()

    view
    |> element("#record-detail-#{rec.id} form:has(input[value=title])")
    |> render_change(%{"key" => "title", "value" => "After"})

    {:ok, reloaded} = Objects.get_record(rec.id, actor: ctx.user, tenant: ctx.ws.id)
    assert reloaded.fields["title"] == "After"
    assert reloaded.title == "After"
  end

  test "moving from the slide-over transitions the record", ctx do
    {:ok, states} =
      Objects.list_workflow_states(ctx.task.workflow_id, actor: ctx.user, tenant: ctx.ws.id)

    todo = Enum.find(states, &(&1.category == :todo))

    {:ok, rec} =
      Objects.create_record(ctx.task.id, %{fields: %{"title" => "Mover"}},
        actor: ctx.user,
        tenant: ctx.ws.id
      )

    {:ok, view, _} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/tasks")
    view |> element("#task-#{rec.id}") |> render_click()

    view
    |> element("#record-detail-#{rec.id} button[phx-value-to='#{todo.id}']")
    |> render_click()

    {:ok, reloaded} = Objects.get_record(rec.id, actor: ctx.user, tenant: ctx.ws.id)
    assert reloaded.state_id == todo.id
  end
end
