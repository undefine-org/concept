defmodule ConceptWeb.WorkspaceGraphTest do
  use ConceptWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "graph#{System.unique_integer([:positive])}@example.com",
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

    {:ok, conn: conn, user: user, ws: ws}
  end

  test "empty workspace shows message", %{conn: conn, ws: ws} do
    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/graph")
    assert html =~ "Add pages to see the graph"
  end

  test "5-page workspace shows nodes", %{conn: conn, ws: ws, user: user} do
    for i <- 1..5 do
      {:ok, _page} =
        Pages.create_page("Graph Page #{i}", ws.id, nil, actor: user, tenant: ws.id)
    end

    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/graph")
    assert extract_data_attr(html, "data-nodes-count") >= 5
  end

  test "authored link appears as edge", %{conn: conn, ws: ws, user: user} do
    {:ok, page_a} =
      Pages.create_page("Page A", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, page_b} =
      Pages.create_page("Page B", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block_a} =
      Pages.create_block(page_a.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, block_b} =
      Pages.create_block(page_b.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, _link} =
      Knowledge.create_link(
        %{
          source_block_id: block_a.id,
          target_block_id: block_b.id,
          kind: :relates_to,
          workspace_id: ws.id
        },
        actor: user,
        tenant: ws.id
      )

    {:ok, _view, html} = live(conn, ~p"/w/#{ws.slug}/graph")
    assert extract_data_attr(html, "data-edges-count") > 0
  end

  defp extract_data_attr(html, attr) do
    case Regex.run(~r/#{attr}="(\d+)"/, html) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end
end
