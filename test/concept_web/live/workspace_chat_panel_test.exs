defmodule ConceptWeb.WorkspaceChatPanelTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Profiles
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "chat#{System.unique_integer([:positive])}@example.com",
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

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "⌘J toggles chat panel visibility", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Initial state: closed
    refute render(view) =~ "ora-chat-panel--open"

    # Press ⌘J to open
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    :timer.sleep(50)
    assert render(view) =~ "ora-chat-panel--open"

    # Press ⌘J again to close
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    :timer.sleep(50)
    refute render(view) =~ "ora-chat-panel--open"
  end

  test "Esc closes chat panel", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Open panel first
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    :timer.sleep(50)
    assert render(view) =~ "ora-chat-panel--open"

    # Press Esc to close
    view
    |> element("#workspace-root")
    |> render_hook("escape", %{})

    :timer.sleep(50)
    refute render(view) =~ "ora-chat-panel--open"
  end

  test "scope dropdown renders 3 scope buttons", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Open chat panel (toggle_chat is synchronous).
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    # Assert on the actual scope buttons (phx-value-scope), not leaky generic
    # text like "workspace"/"page" which the layout/URLs render regardless.
    for scope <- ~w(workspace page subtree) do
      assert has_element?(
               view,
               ~s{button[phx-click="set_scope"][phx-value-scope="#{scope}"]}
             ),
             "expected a scope button for #{scope}"
    end
  end

  test "profile dropdown renders all profile names", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Open chat panel (toggle_chat is synchronous).
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    html = render(view)

    for profile <- Profiles.list() do
      assert html =~ to_string(profile.name)
    end
  end

  test "PubSub palette_ask opens panel and seeds prompt", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Send palette_ask event
    send(view.pid, {:palette_ask, "What is the meaning of life?"})

    :timer.sleep(50)

    html = render(view)
    assert html =~ "ora-chat-panel--open"
    assert html =~ "What is the meaning of life?"
  end

  test "chat panel renders with message form", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    # Open chat panel
    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    :timer.sleep(50)

    # Should have the host-aware composer (PLAN-010 §6.3): assert on the stable
    # composer element id rather than placeholder copy, which now varies by host.
    assert has_element?(view, "[id$=-composer]")
    assert render(view) =~ "Send"
  end

  test "sending a message renders it without crashing (PLAN-010 §6.1)", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}")

    view
    |> element("#workspace-root")
    |> render_hook("toggle_chat", %{})

    :timer.sleep(50)

    # First workspace message find-or-creates a conversation and the LiveView
    # navigates to it (?c=<id>). Following navigation re-mounts the component on
    # the now-loaded conversation, which is what previously crashed render when
    # a broadcast-clause update bypassed the host/composer assigns.
    result =
      view
      |> element("[id$=-composer] form")
      |> render_submit(%{"form" => %{"text" => "Hello host"}})

    {:ok, view, html} =
      case result do
        {:error, {:live_redirect, %{to: to}}} -> live(conn, to)
        {:error, {:redirect, %{to: to}}} -> live(conn, to)
        html when is_binary(html) -> {:ok, view, html}
      end

    :timer.sleep(50)
    html = if html =~ "Hello host", do: html, else: render(view)

    # The message renders (human bubble) and the host-aware rail is present
    # without raising in the sender_kind / participant helpers.
    assert html =~ "Hello host"
    assert has_element?(view, "[id$=-participant-rail]")
  end
end
