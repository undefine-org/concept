defmodule ConceptWeb.RecordRefSeamTest do
  @moduledoc """
  Thread ② — the non-redundancy seam, reachable by a human. A `record_ref`
  block starts unlinked; the page editor exposes a picker that searches records
  by title and, on select, sets the block's `record_id` prop. The block then
  renders the referenced record's live state/title — one canonical record,
  referenced from a document, never copied (docs/objects_and_tasks.md §2).
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Objects
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "seam#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Spec", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, type} = Objects.scaffold_object_type("Ticket", actor: user, tenant: ws.id)

    {:ok, rec} =
      Objects.create_record(type.id, %{fields: %{"title" => "Ship the seam"}},
        actor: user,
        tenant: ws.id
      )

    {:ok, block} =
      Pages.create_block(page.id, :record_ref, ws.id, nil, actor: user, tenant: ws.id)

    %{conn: conn, user: user, ws: ws, page: page, type: type, rec: rec, block: block}
  end

  test "an unlinked record_ref block shows a Link affordance", %{
    conn: conn,
    ws: ws,
    page: page,
    block: block
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    editor = find_live_child(view, "page-editor-#{page.id}")

    assert has_element?(
             editor,
             ~s([phx-click="open_record_picker"][phx-value-block="#{block.id}"])
           )
  end

  test "opening the picker and selecting a record links it and renders live state", %{
    conn: conn,
    ws: ws,
    page: page,
    block: block,
    rec: rec,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    editor = find_live_child(view, "page-editor-#{page.id}")

    # open the picker for this block
    editor
    |> element(~s([phx-click="open_record_picker"][phx-value-block="#{block.id}"]))
    |> render_click()

    # the picker lists the candidate record by title
    assert has_element?(editor, "#record-picker")
    assert render(editor) =~ "Ship the seam"

    # select it
    editor
    |> element(~s(#record-picker [phx-value-record="#{rec.id}"]))
    |> render_click()

    # block prop persisted
    {:ok, reloaded} = Pages.get_block(block.id, actor: user, tenant: ws.id)
    assert reloaded.props["record_id"] == rec.id

    # block now renders the record's live title (not "Unlinked record")
    html = render(editor)
    assert html =~ "Ship the seam"
    refute html =~ "Unlinked record"
  end

  test "picker search narrows by title", %{
    conn: conn,
    ws: ws,
    page: page,
    block: block,
    type: type,
    user: user
  } do
    {:ok, _other} =
      Objects.create_record(type.id, %{fields: %{"title" => "Totally different"}},
        actor: user,
        tenant: ws.id
      )

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    editor = find_live_child(view, "page-editor-#{page.id}")

    editor
    |> element(~s([phx-click="open_record_picker"][phx-value-block="#{block.id}"]))
    |> render_click()

    html =
      editor
      |> form("#record-picker form", %{"query" => "seam"})
      |> render_change()

    assert html =~ "Ship the seam"
    refute html =~ "Totally different"
  end
end
