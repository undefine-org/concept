defmodule ConceptWeb.CompositeBlocksTest do
  @moduledoc """
  LiveView tests for FEAT-050 composite blocks.

  Covers the `insert_composite_below` server handler dispatched from the
  composite picker overlay; verifies the resulting Table/Columns parent
  renders as a grid with addressable cells.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "comp_lv_#{System.unique_integer([:positive])}@example.com",
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
      |> Ash.Query.for_read(:sign_in_with_password, %{
        email: user.email,
        password: "passw0rd!"
      })
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Composite LV", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "insert_composite_below table creates 1 parent + 6 cells and renders grid",
       %{conn: conn, user: user, ws: ws, page: page} do
    {:ok, above} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_composite_below", %{
      "type" => "table",
      "rows" => 2,
      "cols" => 3,
      "block_id" => above.id
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1 + 1 + 6

    table_parent = Enum.find(blocks, &(&1.type == :table))
    assert table_parent

    cells = Enum.filter(blocks, &(&1.parent_block_id == table_parent.id))
    assert length(cells) == 6

    html = render(view)
    assert html =~ "ora-composite-table"
    first_cell = cells |> Enum.sort_by(& &1.position) |> List.first()
    assert html =~ first_cell.id
  end

  test "insert_composite_below columns creates 1 parent + N children and renders grid",
       %{conn: conn, user: user, ws: ws, page: page} do
    {:ok, above} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_composite_below", %{
      "type" => "columns",
      "count" => 3,
      "block_id" => above.id
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1 + 1 + 3

    cols_parent = Enum.find(blocks, &(&1.type == :columns))
    assert cols_parent

    children = Enum.filter(blocks, &(&1.parent_block_id == cols_parent.id))
    assert length(children) == 3

    html = render(view)
    assert html =~ "ora-composite-columns"
  end

  test "table cells render as editable ora-blocks, not empty anchor divs",
       %{conn: conn, user: user, ws: ws, page: page} do
    {:ok, _table} =
      Pages.create_table(ws.id, page.id, 2, 3, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    html = render(view)

    # Each table cell must render as an editable <ora-block ... block-type="table_cell">,
    # not as a content-less <div class="block-anchor"></div>.
    cell_blocks = Regex.scan(~r/<ora-block[^>]*block-type="table_cell"/, html)

    assert length(cell_blocks) == 6,
           "expected 6 ora-block elements with block-type=\"table_cell\"; got #{length(cell_blocks)}"

    # The BlockEditor hook must be attached on every cell so it is typable.
    hook_blocks =
      Regex.scan(~r/<ora-block[^>]*phx-hook="BlockEditor"[^>]*block-type="table_cell"/, html)

    assert length(hook_blocks) == 6
  end

  test "C-6: columns render resize handles and a ratio-driven grid template",
       %{conn: conn, user: user, ws: ws, page: page} do
    {:ok, above} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_composite_below", %{
      "type" => "columns",
      "count" => 3,
      "block_id" => above.id
    })

    html = render(view)

    # The CompositeResize hook is attached and there is one fewer handle than
    # columns (handles sit BETWEEN tracks).
    assert html =~ ~s(phx-hook="CompositeResize")
    handles = Regex.scan(~r/ora-column-resizer/, html)
    assert length(handles) == 2, "expected 2 resizers for 3 columns"

    # Grid is driven by fr ratios, not a repeat(1fr) fallback.
    assert html =~ "grid-template-columns:"
    assert html =~ "fr"
  end

  test "C-6: resize_columns persists new ratios",
       %{conn: conn, user: user, ws: ws, page: page} do
    {:ok, above} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor = find_live_child(view, "page-editor-#{page.id}")

    render_hook(editor, "insert_composite_below", %{
      "type" => "columns",
      "count" => 2,
      "block_id" => above.id
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    cols = Enum.find(blocks, &(&1.type == :columns))

    render_hook(editor, "resize_columns", %{
      "block_id" => cols.id,
      "ratios" => [0.7, 0.3]
    })

    {:ok, after_blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    updated = Enum.find(after_blocks, &(&1.id == cols.id))
    ratios = get_in(updated.props, ["ratios"])

    assert [r1, r2] = ratios
    assert_in_delta r1, 0.7, 0.001
    assert_in_delta r2, 0.3, 0.001
  end

  test "C-6: the Composite flavour declares resizable? true by default" do
    assert Concept.Pages.BlockTypes.Columns.resizable?()
    assert Concept.Pages.BlockTypes.Table.resizable?()
  end
end
