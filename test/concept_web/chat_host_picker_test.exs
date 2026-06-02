defmodule ConceptWeb.ChatHostPickerTest do
  @moduledoc """
  T1 — the host-picker. Starting a conversation means choosing a host
  (workspace / page / …). The global "+ New conversation" opens the picker;
  selecting a host + optional topic creates a conversation about that host.
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
        email: "picker#{System.unique_integer([:positive])}@example.com",
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

    {:ok, [_ | _] = wss} = Accounts.Workspace.for_user(user.id, actor: user)
    ws = hd(wss)
    {:ok, page} = Pages.create_page("Offline Sync", ws.id, nil, actor: user, tenant: ws.id)
    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  defp open_chat(view) do
    view |> element("#workspace-root") |> render_hook("toggle_chat", %{})
    :timer.sleep(80)
  end

  test "the New conversation button opens the host-picker", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)

    view |> element("[id$='-new-conversation']") |> render_click()
    html = render(view)

    # The picker is open: shows host sections + the workspace + the page host.
    assert html =~ "Start a conversation" or html =~ "host-picker"
    assert html =~ "Offline Sync"
    assert html =~ "Workspace"
  end

  test "picking the workspace host creates a workspace conversation", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    view |> element("[id$='-new-conversation']") |> render_click()

    before = Chat.my_conversations!(actor: ctx.user, tenant: ctx.ws.id) |> length()

    view
    |> element("[phx-click='start_conversation'][phx-value-host-type='workspace']")
    |> render_click()

    :timer.sleep(120)
    after_ = Chat.my_conversations!(actor: ctx.user, tenant: ctx.ws.id) |> length()
    assert after_ == before + 1
  end

  test "picking a page host creates a conversation about that page", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    view |> element("[id$='-new-conversation']") |> render_click()

    view
    |> element(
      "[phx-click='start_conversation'][phx-value-host-type='page'][phx-value-host-id='#{ctx.page.id}']"
    )
    |> render_click()

    :timer.sleep(120)

    convs =
      Chat.conversations_for_host!(:page, ctx.page.id, actor: ctx.user, tenant: ctx.ws.id)

    assert length(convs) >= 1
  end

  test "the picker filters hosts by the search query", ctx do
    {:ok, _p2} =
      Pages.create_page("Q3 Roadmap", ctx.ws.id, nil, actor: ctx.user, tenant: ctx.ws.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/w/#{ctx.ws.slug}")
    open_chat(view)
    view |> element("[id$='-new-conversation']") |> render_click()

    view
    |> element("[id$='-host-picker'] form")
    |> render_change(%{"q" => "Offline"})

    # Scope the assertion to the picker dialog (Q3 Roadmap also appears in the
    # workspace sidebar tree, which is irrelevant to the filter).
    picker_html =
      view |> element("[id$='-host-picker-dialog']") |> render()

    assert picker_html =~ "Offline Sync"
    refute picker_html =~ "Q3 Roadmap"
  end
end
