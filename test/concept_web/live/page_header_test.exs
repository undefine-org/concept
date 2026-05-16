defmodule ConceptWeb.PageHeaderTest do
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

  test "page header live_component is present", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "#page-header-#{page.id}")
  end

  test "title element is contenteditable", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    assert has_element?(view, "h1#page-title-#{page.id}[contenteditable=\"true\"]")
  end

  test "save_title updates the page", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    # Find the PageHeader live_component and trigger save_title
    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => "Renamed"})

    # Verify the page was renamed in DB
    {:ok, updated} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    assert updated.title == "Renamed"
  end

  test "renamed title appears in rendered output", %{conn: conn, ws: ws, page: page} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => "Renamed"})

    # Re-render and check title appears
    html = render(view)
    assert html =~ "Renamed"
  end

  test "empty title falls back to placeholder", %{conn: conn, ws: ws, page: page, user: user} do
    {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header = element(view, "#page-header-#{page.id}")
    render_hook(header, "save_title", %{"value" => ""})

    # Title element should be empty (placeholder handled by CSS ::before)
    assert has_element?(view, "h1#page-title-#{page.id}")

    # Check page is empty title in DB
    {:ok, updated} = Pages.get_page(page.id, actor: user, tenant: ws.id)
    assert updated.title == ""
  end

  test "remote save_title updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "save_title", %{"value" => "Renamed"})

    Process.sleep(100)
    html2 = render(view2)
    assert html2 =~ "Renamed"
    assert has_element?(view2, "h1#page-title-#{page.id}", "Renamed")
  end

  test "remote set_emoji updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "set_emoji", %{"emoji" => "🚀"})

    Process.sleep(100)
    html2 = render(view2)
    assert html2 =~ "🚀"
  end

  test "remote set_cover_color updates other LV's page header", %{conn: conn, ws: ws, page: page} do
    {:ok, view1, _html1} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")
    {:ok, view2, _html2} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

    header1 = element(view1, "#page-header-#{page.id}")
    render_hook(header1, "set_cover_color", %{"color" => "blue"})

    Process.sleep(100)
    html2 = render(view2)
    assert html2 =~ "ora-cover-blue"
  end
end
