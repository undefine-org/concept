defmodule ConceptWeb.AskSelectionTest do
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
        email: "ask_test#{System.unique_integer([:positive])}@example.com",
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
    {:ok, page} = Pages.create_page("Test Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "ask_selection event broadcasts palette_ask_with_seed", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    # Subscribe to the palette topic
    Phoenix.PubSub.subscribe(Concept.PubSub, "palette:#{ws.id}")

    # Mount the page editor
    user_id = user.id
    user_email = user.email

    {:ok, _view, _html} =
      live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    # The PageEditorLive is rendered as a separate LiveView via live_render
    # We need to find the page editor element and trigger the event on it
    # For now, let's test the handler directly by sending the message to the pid

    # Find the page editor LiveView - it should be a child process
    # For testing, we'll send the broadcast and verify it's received

    # Simulate the ask_selection event by calling handle_event on PageEditorLive
    # We need to get the PageEditorLive pid from the nested render

    # Get the editor session
    editor_session = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user_id,
      "user_email" => user_email
    }

    {:ok, editor_view, _html} =
      conn
      |> Phoenix.ConnTest.init_test_session(editor_session)
      |> live_isolated(ConceptWeb.PageEditorLive, session: editor_session)

    # Trigger the ask_selection event
    _result =
      editor_view
      |> element("#page-editor-root")
      |> render_hook("ask_selection", %{
        "text" => "test excerpt",
        "block_id" => "block-123",
        "page_id" => page.id
      })

    # Verify the broadcast was sent
    assert_receive {:palette_ask_with_seed, "test excerpt", page_id}
    assert page_id == page.id
  end

  test "palette_ask_with_seed opens ChatPanel with seeded prompt", %{
    conn: conn,
    ws: ws,
    page: page
  } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    # Send the palette_ask_with_seed message
    send(view.pid, {:palette_ask_with_seed, "test excerpt", page.id})

    :timer.sleep(50)

    html = render(view)

    # Chat panel should be open
    assert html =~ "ora-chat-panel--open"

    # Should have the seeded prompt
    assert html =~ "Tell me more about this excerpt"
    assert html =~ "test excerpt"

    # Scope should be set to subtree (check for active button)
    assert html =~ "subtree"
  end

  test "empty text in ask_selection still broadcasts", %{
    conn: conn,
    ws: ws,
    page: page,
    user: user
  } do
    Phoenix.PubSub.subscribe(Concept.PubSub, "palette:#{ws.id}")

    editor_session = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user.id,
      "user_email" => user.email
    }

    {:ok, editor_view, _html} =
      conn
      |> Phoenix.ConnTest.init_test_session(editor_session)
      |> live_isolated(ConceptWeb.PageEditorLive, session: editor_session)

    editor_view
    |> element("#page-editor-root")
    |> render_hook("ask_selection", %{
      "text" => "",
      "block_id" => nil,
      "page_id" => page.id
    })

    assert_receive {:palette_ask_with_seed, "", page_id}
    assert page_id == page.id
  end
end
