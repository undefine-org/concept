defmodule ConceptWeb.ChatSearchTest do
  @moduledoc """
  R5 — rail search. A filter input narrows the conversation rail by a
  case-insensitive substring on the conversation title OR its host label,
  client-driven over the already-loaded list. Empty query restores the full
  rail; a no-match query shows a tailored empty state.
  """
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Knowledge.Chat
  alias Concept.Pages
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "search#{System.unique_integer([:positive])}@example.com",
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

    {:ok, [ws | _]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("Migrations", ws.id, nil, actor: user, tenant: ws.id)

    # A workspace topic and a page-hosted topic, so we can match on both title
    # and host label.
    {:ok, ws_msg} =
      Chat.create_message(%{text: "workspace-only banter", addresses_host: false},
        actor: user,
        tenant: ws.id
      )

    {:ok, _pg_msg} =
      Chat.create_message(
        %{text: "page topic", addresses_host: true, host_type: :page, host_id: page.id},
        actor: user,
        tenant: ws.id
      )

    {:ok, conn: conn, user: user, ws: ws, page: page, ws_conv: ws_msg.conversation_id}
  end

  test "the rail search input is present in full-screen Channels", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")
    assert has_element?(view, "[id$='-rail-search']")
  end

  test "typing a host name narrows the rail to that host's conversations", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")

    # Before: both the workspace topic and the Migrations page topic are shown.
    assert render(view) =~ "Migrations"

    # Filter by the page host label.
    view
    |> element("form[phx-change='filter_rail']")
    |> render_change(%{"rail_query" => "migrations"})

    html = render(view)
    assert html =~ "Migrations"
    # The workspace-hosted topic's section header ("Workspace") falls away.
    refute html =~ "workspace-only banter"
  end

  test "a no-match query shows the tailored empty state", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}/channels")

    view
    |> element("form[phx-change='filter_rail']")
    |> render_change(%{"rail_query" => "zzz-no-such-topic"})

    assert render(view) =~ "No conversations match"
  end
end
