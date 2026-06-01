defmodule ConceptWeb.LockIndicatorTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user1} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "lock_user1_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, user2} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "lock_user2_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    for u <- [user1, user2] do
      Repo.update_all(
        from(usr in Concept.Accounts.User, where: usr.id == ^u.id),
        set: [confirmed_at: DateTime.utc_now()]
      )
    end

    # Sign in user1
    {:ok, signed_in1} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user1.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn1 =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in1.__metadata__.token)

    # Sign in user2
    {:ok, signed_in2} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user2.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn2 =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in2.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user1.id, actor: user1)

    # Add user2 to the workspace so they can read blocks
    {:ok, _} =
      Concept.Accounts.Membership.create(ws.id, user2.id, :member, authorize?: false)

    {:ok, page} = Pages.create_page("Lock Test", ws.id, nil, actor: user1, tenant: ws.id)

    {:ok, block} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user1, tenant: ws.id)

    {:ok,
     conn1: conn1, conn2: conn2, user1: user1, user2: user2, ws: ws, page: page, block: block}
  end

  test "peer sees data-locked-by when other user focuses block", %{
    conn1: conn1,
    conn2: conn2,
    user1: user1,
    user2: user2,
    ws: ws,
    page: page,
    block: block
  } do
    session1 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user1.id,
      "user_email" => user1.email
    }

    {:ok, view1, _html} =
      conn1
      |> Phoenix.ConnTest.init_test_session(session1)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session1)

    session2 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user2.id,
      "user_email" => user2.email
    }

    {:ok, view2, _html} =
      conn2
      |> Phoenix.ConnTest.init_test_session(session2)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session2)

    # Let presence state settle
    :timer.sleep(200)

    view1
    |> element("#page-editor-root")
    |> render_hook("focus_block", %{"block_id" => block.id})

    :timer.sleep(200)

    html2 = render(view2)

    assert html2 =~ "data-locked-by=\"#{user1.id}\""
    assert html2 =~ "--lock-color: #{ConceptWeb.Colors.for_user_id(user1.id)}"

    # Self-LV must not see its own lock indicator
    html1 = render(view1)
    refute html1 =~ "data-locked-by=\"#{user1.id}\""
  end

  test "blur_block removes lock indicator for peer", %{
    conn1: conn1,
    conn2: conn2,
    user1: user1,
    user2: user2,
    ws: ws,
    page: page,
    block: block
  } do
    session1 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user1.id,
      "user_email" => user1.email
    }

    {:ok, view1, _html} =
      conn1
      |> Phoenix.ConnTest.init_test_session(session1)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session1)

    session2 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user2.id,
      "user_email" => user2.email
    }

    {:ok, view2, _html} =
      conn2
      |> Phoenix.ConnTest.init_test_session(session2)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session2)

    :timer.sleep(200)

    view1
    |> element("#page-editor-root")
    |> render_hook("focus_block", %{"block_id" => block.id})

    :timer.sleep(200)
    assert render(view2) =~ "data-locked-by=\"#{user1.id}\""

    view1
    |> element("#page-editor-root")
    |> render_hook("blur_block", %{"block_id" => block.id})

    :timer.sleep(200)
    refute render(view2) =~ "data-locked-by=\"#{user1.id}\""
  end

  test "C-2: each peer sees the OTHER collaborator in the presence bar, not itself",
       %{conn1: conn1, conn2: conn2, user1: user1, user2: user2, ws: ws, page: page} do
    session1 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user1.id,
      "user_email" => user1.email
    }

    {:ok, view1, _html} =
      conn1
      |> Phoenix.ConnTest.init_test_session(session1)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session1)

    session2 = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user2.id,
      "user_email" => user2.email
    }

    {:ok, view2, _html} =
      conn2
      |> Phoenix.ConnTest.init_test_session(session2)
      |> live_isolated(ConceptWeb.PageEditorLive, session: session2)

    :timer.sleep(250)

    html1 = render(view1)
    html2 = render(view2)

    # The bar appears ("Active") and each viewer sees the other's colour avatar,
    # but NOT their own (collaborators excludes self).
    assert html1 =~ "Active"
    assert html1 =~ "background-color: #{ConceptWeb.Colors.for_user_id(user2.id)}"
    refute html1 =~ "background-color: #{ConceptWeb.Colors.for_user_id(user1.id)}"

    assert html2 =~ "background-color: #{ConceptWeb.Colors.for_user_id(user1.id)}"
    refute html2 =~ "background-color: #{ConceptWeb.Colors.for_user_id(user2.id)}"
  end
end
