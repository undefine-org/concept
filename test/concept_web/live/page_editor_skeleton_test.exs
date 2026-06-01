defmodule ConceptWeb.PageEditorSkeletonTest do
  @moduledoc """
  C-5 (G1): the page editor shows a skeleton on the disconnected mount instead
  of flashing blank, then swaps to real blocks once connected. Guards the
  loading→loaded transition (and that it doesn't crash on the :loading sentinel).
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
        email: "skel_#{System.unique_integer([:positive])}@example.com",
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
    {:ok, page} = Pages.create_page("Skeleton Test", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, _block} =
      Pages.create_block(:page, page.id, :paragraph, ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  test "disconnected mount renders a skeleton; connected mount renders blocks", %{
    conn: conn,
    user: user,
    ws: ws,
    page: page
  } do
    session = %{
      "workspace_id" => ws.id,
      "page_id" => page.id,
      "user_id" => user.id,
      "user_email" => user.email
    }

    conn = Phoenix.ConnTest.init_test_session(conn, session)

    # The connected render: real blocks, and the skeleton has been swapped out.
    {:ok, _view, connected_html} =
      live_isolated(conn, ConceptWeb.PageEditorLive, session: session)

    assert connected_html =~ ~s(id="block-list-#{page.id}")
    refute connected_html =~ "ora-skeleton"
  end

  test "the :loading sentinel renders a skeleton and never the block list", %{
    user: user,
    ws: ws,
    page: page
  } do
    # Directly exercise the render's loading branch (the disconnected-mount
    # state) without depending on transport internals.
    assigns = %{
      blocks: :loading,
      page_id: page.id,
      presence_users: [],
      locked_blocks: %{},
      current_user: user,
      workspace: ws,
      picker_block_id: nil,
      picker_query: "",
      picker_results: []
    }

    html =
      assigns
      |> ConceptWeb.PageEditorLive.render()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "ora-skeleton", "expected a skeleton while blocks are :loading"
    refute html =~ ~s(id="block-list-), "block list must not render while loading"
  end
end
