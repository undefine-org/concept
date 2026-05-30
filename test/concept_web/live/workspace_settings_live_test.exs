defmodule ConceptWeb.WorkspaceSettingsLiveTest do
  use ConceptWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Concept.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ws_settings_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user, ws: ws}
  end

  test "renders Members tab with owner", %{conn: conn, ws: ws, user: user} do
    {:ok, view, html} = live(conn, ~p"/w/#{ws.slug}/settings")
    assert html =~ "Settings"
    assert html =~ "Members"
    assert has_element?(view, "#members-tab")
    assert html =~ to_string(user.email)
  end

  test "add_member by a second registered user's email adds them", %{conn: conn, ws: ws} do
    {:ok, other} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "other_#{System.unique_integer([:positive])}@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create(authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/settings")

    view
    |> form("#add-member-form", %{"email" => other.email})
    |> render_submit()

    assert render(view) =~ to_string(other.email)
    assert has_element?(view, "[id^='member-']")
  end

  test "add unknown email shows error flash", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/settings")

    html =
      view
      |> form("#add-member-form", %{"email" => "nobody@example.com"})
      |> render_submit()

    assert html =~ "No user with that email"
  end

  test "switch to API keys tab; issue a key → plaintext shown once; list shows the key; revoke removes it",
       %{
         conn: conn,
         ws: ws
       } do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/settings")

    # Switch to API keys tab
    view
    |> element("button[phx-value-tab='api_keys']")
    |> render_click()

    assert has_element?(view, "#api-keys-tab")

    # Issue a key
    html =
      view
      |> form("#issue-key-form", %{"name" => "Test key"})
      |> render_submit()

    assert has_element?(view, "#new-plaintext-box")
    assert html =~ "Copy this key now"

    # The key should appear in the list
    assert has_element?(view, "[id^='api-key-']")

    # Extract the key id from the DOM so we can revoke it
    key_id =
      view
      |> render()
      |> then(fn html ->
        case Regex.run(~r/id="api-key-([^"]+)"/, html) do
          [_, id] -> id
          _ -> nil
        end
      end)

    assert key_id != nil

    # Revoke the key
    view
    |> element("#revoke-key-#{key_id}")
    |> render_click()

    refute has_element?(view, "#api-key-#{key_id}")
  end
end
