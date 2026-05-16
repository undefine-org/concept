defmodule ConceptWeb.PageEditorTest do
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
        email: "palette#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Confirm user directly
    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    # Sign in to get token
    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Roadmap", ws.id, nil, actor: user, tenant: ws.id)
    _ = Pages.create_page("Meeting Notes", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  # ── BUG-001 ──────────────────────────────────────────────────────────

  test "block-handle renders per text block", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, _block} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "ora-block-handle")

    {:ok, _block2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view2, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    handles = LazyHTML.query(LazyHTML.from_fragment(render(view2)), "ora-block-handle")
    assert Enum.count(handles) == 2
  end

  test "format toolbar renders exactly once on page", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    # 0 blocks
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    toolbars = LazyHTML.query(LazyHTML.from_fragment(render(view)), "ora-format-toolbar")
    assert Enum.count(toolbars) == 1

    # 1 block
    {:ok, _} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view2, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    toolbars2 = LazyHTML.query(LazyHTML.from_fragment(render(view2)), "ora-format-toolbar")
    assert Enum.count(toolbars2) == 1

    # 2 blocks
    {:ok, _} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view3, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    toolbars3 = LazyHTML.query(LazyHTML.from_fragment(render(view3)), "ora-format-toolbar")
    assert Enum.count(toolbars3) == 1
  end

  test "handle row layout class present", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, _} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, ".ora-block-row")
  end

  # ── BUG-002 ──────────────────────────────────────────────────────────

  test "insert_paragraph_below creates new block at tail", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, block} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_paragraph_below", %{"block_id" => block.id})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 2
    new_block = Enum.find(blocks, &(&1.id != block.id))
    assert new_block.position > block.position

    new_block_id = new_block.id
    assert_push_event(view, "focus_block_caret", %{block_id: new_block_id, position: "start"})
  end

  test "insert_paragraph_below between siblings", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, block_a} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block_b} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_paragraph_below", %{"block_id" => block_a.id})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 3
    new_block = Enum.find(blocks, &(&1.id != block_a.id && &1.id != block_b.id))
    assert new_block.position > block_a.position
    assert new_block.position < block_b.position
  end

  test "nav_block down focuses next block", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, block1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    block2_id = block2.id

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("nav_block", %{"direction" => "down", "block_id" => block1.id})

    assert_push_event(view, "focus_block_caret", %{block_id: block2_id, position: "start"})
  end

  test "nav_block up focuses previous block", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, block1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    block1_id = block1.id

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("nav_block", %{"direction" => "up", "block_id" => block2.id})

    assert_push_event(view, "focus_block_caret", %{block_id: block1_id, position: "end"})
  end

  test "nav_block up at first block is no-op", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, block1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("nav_block", %{"direction" => "up", "block_id" => block1.id})

    refute_push_event(view, "focus_block_caret", %{}, 100)
  end

  test "delete_block_merge archives empty block and focuses previous", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, block1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("delete_block_merge", %{"block_id" => block2.id})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1

    block1_id = block1.id
    assert_push_event(view, "focus_block_caret", %{block_id: block1_id, position: "end"})
  end

  test "delete_block_merge on only block is no-op", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, block} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("delete_block_merge", %{"block_id" => block.id})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1
  end

  test "block_created does not produce duplicates", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("add_first_block", %{})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1

    doc = LazyHTML.from_fragment(render(view))
    block_els = LazyHTML.query(doc, "ora-block")
    assert Enum.count(block_els) == 1
  end

  # ── BUG-018 ──────────────────────────────────────────────────────────

  test "reorder_block moves block to first position", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, b1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b3} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor_view = find_live_child(view, "page-editor-#{page.id}")

    # Move b3 to first position: prev_id = nil, next_id = b1.id
    render_hook(editor_view, "reorder_block", %{
      "block_id" => b3.id,
      "prev_id" => nil,
      "next_id" => b1.id
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    ids = Enum.map(blocks, & &1.id)
    assert ids == [b3.id, b1.id, b2.id]
  end

  test "reorder_block moves block to last position", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, b1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b3} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor_view = find_live_child(view, "page-editor-#{page.id}")

    # Move b1 to last position: prev_id = b3.id, next_id = nil
    render_hook(editor_view, "reorder_block", %{
      "block_id" => b1.id,
      "prev_id" => b3.id,
      "next_id" => nil
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    ids = Enum.map(blocks, & &1.id)
    assert ids == [b2.id, b3.id, b1.id]
  end

  test "reorder_block moves block to middle position", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, b1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b3} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor_view = find_live_child(view, "page-editor-#{page.id}")

    # Move b3 between b1 and b2: prev_id = b1.id, next_id = b2.id
    render_hook(editor_view, "reorder_block", %{
      "block_id" => b3.id,
      "prev_id" => b1.id,
      "next_id" => b2.id
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    ids = Enum.map(blocks, & &1.id)

    # Read positions and assert strict ordering (BUG-018 invariant)
    rb1 = Enum.find(blocks, &(&1.id == b1.id))
    rb3 = Enum.find(blocks, &(&1.id == b3.id))
    rb2 = Enum.find(blocks, &(&1.id == b2.id))
    assert rb1.position < rb3.position
    assert rb3.position < rb2.position
    assert ids == [b1.id, b3.id, b2.id]
  end

  test "reorder_block is no-op when dropped at same position", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, b1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, b2} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor_view = find_live_child(view, "page-editor-#{page.id}")

    # Move b2 to where it already is: prev_id = b1.id, next_id = nil
    render_hook(editor_view, "reorder_block", %{
      "block_id" => b2.id,
      "prev_id" => b1.id,
      "next_id" => nil
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    ids = Enum.map(blocks, & &1.id)
    assert ids == [b1.id, b2.id]
  end

  test "reorder_block with unknown block_id is safe no-op", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, b1} =
      Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    editor_view = find_live_child(view, "page-editor-#{page.id}")

    render_hook(editor_view, "reorder_block", %{
      "block_id" => "nonexistent",
      "prev_id" => nil,
      "next_id" => nil
    })

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 1
  end

  # ── BUG-016 ──────────────────────────────────────────────────────────

  test "link editor host renders alongside format toolbar", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "#format-toolbar-host")
    assert has_element?(view, "ora-format-toolbar")
    assert has_element?(view, "ora-link-editor")
  end

  test "bold text in block content renders as <strong>", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    bold_lexical = %{
      "root" => %{
        "type" => "root",
        "children" => [
          %{
            "type" => "paragraph",
            "children" => [
              %{
                "type" => "text",
                "text" => "bold text here",
                "format" => 1,
                "detail" => 0,
                "mode" => "normal",
                "style" => "",
                "version" => 1
              }
            ],
            "direction" => "ltr",
            "format" => "",
            "indent" => 0,
            "version" => 1
          }
        ],
        "direction" => "ltr",
        "format" => "",
        "indent" => 0,
        "version" => 1
      }
    }

    # Pure Lexical→HTML transformation — no DB needed; the block storage path is
    # exercised by other tests, and `update_content` requires holding the lock.
    _ = {conn, ws, page, user}
    html = Concept.Lexical.to_html(bold_lexical)
    assert html =~ "<strong>"
    assert html =~ "bold text here"
  end

  # ── BUG-017 ──────────────────────────────────────────────────────────

  test "insert_block_below with type creates typed block", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, block} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_block_below", %{"block_id" => block.id, "type" => "heading_1"})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 2

    new_block = Enum.find(blocks, &(&1.id != block.id))
    assert new_block.type == :heading_1
    assert new_block.position > block.position

    new_block_id = new_block.id
    assert_push_event(view, "focus_block_caret", %{block_id: new_block_id, position: "start"})
  end

  test "insert_block_below backward compat insert_paragraph_below creates paragraph", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    {:ok, block} = Pages.create_block(page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    view
    |> find_live_child("page-editor-#{page.id}")
    |> render_hook("insert_paragraph_below", %{"block_id" => block.id})

    {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
    assert length(blocks) == 2

    new_block = Enum.find(blocks, &(&1.id != block.id))
    assert new_block.type == :paragraph
  end
end
